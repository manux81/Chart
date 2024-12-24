/*
 MIT License

 Copyright (c) 2024 Manuele Conti

 Permission is hereby granted, free of charge, to any person obtaining a copy
 of this software and associated documentation files (the "Software"), to deal
 in the Software without restriction, including without limitation the rights
 to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 copies of the Software, and to permit persons to whom the Software is
 furnished to do so, subject to the following conditions:

 The above copyright notice and this permission notice shall be included in all
 copies or substantial portions of the Software.

 THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
 SOFTWARE.
 */



import UIKit

public protocol ChartDelegate {
	func emitSwipe(direction: Bool)
	func emitLongPress(from sender: Chart)
}



@IBDesignable public class Chart: UIView {
	enum ChartAxisType {
		case atNumeric
		case atDate
	}

	enum ChartDateStrategy {
		case dsNone
		case dsUniformTimeInDay
		case dsUniformDayInMonth
	}

	var tickOriginX: Double = 0.0
	var tickOriginY: Double = 0.0
	var gridColor: UIColor = UIColor(cgColor: CGColorFromRGB(rgbValue: 0xE0E0E0))
	var lineColor: UIColor = UIColor(cgColor: CGColorFromRGB(rgbValue: 0xFF0202))
	var scatterColor: UIColor = UIColor(cgColor: CGColorFromRGB(rgbValue: 0xFF0202))
	var disabledColor: UIColor = .gray
	var textColor: UIColor = .black
	var axisColor: UIColor = .black
	var tickerFormat: String = "HH:mm"
	var balloonFormat: String = "dd MMM yyyy"
	var balloonUM : String = ""
	var tickCountX: UInt = 5
	var tickCountY: UInt = 5
	var tickerTypeX: ChartAxisType = .atNumeric
	var tickerTypeY: ChartAxisType = .atNumeric
	var delegate: ChartDelegate? = nil

	private var baserect: CGRect? = nil
	private var alreadySorted: Bool = true
	private var rangeX: ClosedRange<Double> = 0.0 ... 100.0
	private var rangeY: ClosedRange<Double> = -20.0 ... 150.0
	private var keys: Array<Double> = []
	private var values: Array<Double> = []
	private var status: Array<Bool> = []

	private var panTop: CGFloat = 5.0
	private var panBottom: CGFloat = 15.0
	private var panLeft: CGFloat = 15.0
	private var panRight: CGFloat = 40.0
	private var tickerFont: UIFont?
	private var tickerAttributes: [NSAttributedString.Key: Any]?
	private var selected: Int = -1

	private let unselectedTextBGColor = CGColorFromRGB(rgbValue: 0x888A85)
	private let selectedTextBGColor = CGColorFromRGB(rgbValue: 0xFFFFFF)
	private let dashLengths: [CGFloat] = [7.0, 3.0]
	private let screenScale = 1.0 / UIScreen.main.scale


	private var lminX: Double = 0.0
	private var lmaxX: Double = 0.0
	private var lminY: Double = 0.0
	private var lmaxY: Double = 0.0


	private var ticksX: [Double] = []
	private var ticksY: [Double] = []
	private var tickStepX: Double = 0.0
	private var tickStepY: Double = 0.0

	private var dateStrategy: ChartDateStrategy = .dsNone

	private var recognizerLeft: UISwipeGestureRecognizer?
	private var recognizerRight: UISwipeGestureRecognizer?
	private var recognizerLongPress: UILongPressGestureRecognizer?

	private var balloonPoint: CGPoint? = nil
	private var balloonValue: String? = nil
	private var balloonDate: String? = nil
	private var balloonTimer : Timer? = nil
	private var context: CGContext? = nil



	override init(frame: CGRect) {
		super.init(frame: frame)
		commonInit()
	}

	required init?(coder: NSCoder) {
		super.init(coder: coder)
		commonInit()
	}

	private func commonInit() {
		self.tickerFont = UIFont.systemFont(ofSize: 25.0 * screenScale, weight: UIFont.Weight.bold)
		self.tickerAttributes = [
			NSAttributedString.Key.font: self.tickerFont!,
			NSAttributedString.Key.foregroundColor: self.textColor
		]
		isUserInteractionEnabled = true
		recognizerLongPress = UILongPressGestureRecognizer(target: self, action: #selector(longPress(gestureRecognizer:)))
		recognizerLongPress?.delegate = self
		addGestureRecognizer(recognizerLongPress!)

		recognizerLeft = UISwipeGestureRecognizer(target: self, action: #selector(swipe(gestureRecognizer:)))
		recognizerLeft!.direction = UISwipeGestureRecognizer.Direction.left
		recognizerLeft!.numberOfTouchesRequired = 1
		recognizerLeft!.delegate = self
		addGestureRecognizer(recognizerLeft!)

		recognizerRight = UISwipeGestureRecognizer(target: self, action: #selector(swipe(gestureRecognizer:)))
		recognizerRight!.direction = UISwipeGestureRecognizer.Direction.right
		recognizerRight!.numberOfTouchesRequired = 1
		recognizerRight!.delegate = self
		addGestureRecognizer(recognizerRight!)

		self.becomeFirstResponder()
	}

	public override func layoutSubviews() {
		super.layoutSubviews()
		self.backgroundColor = UIColor.clear
	}

	public override func draw(_ rect: CGRect) {
		let clipArea = CGRect(x: rect.minX + panLeft - 6, y: rect.minY + panTop - 6, width: rect.maxX - panRight - panLeft + 6, height: rect.height - panBottom - panTop + 6)
		baserect = rect

		// Graphic context
		context = UIGraphicsGetCurrentContext()
		CATransaction.begin()
		CATransaction.setDisableActions(true)
		drawGrids()
		drawAxis()
		drawTickers()
		context?.clip(to: clipArea)

		drawSurface()
		drawLines()
		drawScatters()
		if selected != -1 {
			drawBalloon(atPoint: balloonPoint!, value: balloonValue!, date: balloonDate!)
		}
		context?.restoreGState()
		CATransaction.commit()

	}

	@objc func swipe(gestureRecognizer: UISwipeGestureRecognizer!) {
		self.unselect()
		if gestureRecognizer.direction == .left {
			delegate?.emitSwipe(direction: false)
		} else {
			delegate?.emitSwipe(direction: true)
		}
	}

	@objc func longPress(gestureRecognizer: UILongPressGestureRecognizer!) {
		let location = gestureRecognizer.location(in: self)
		let coeX = (baserect!.maxX - panRight - panLeft) / (tickStepX * Double(ticksX.count))
		let coeY = (baserect!.maxY - panBottom - panTop) / (lmaxY - lminY)
		var index = -1
		var pX: Double = 0.0
		var pY: Double = 0.0
		var find = -1
		var distance_min : Double = Double.infinity

		for p in keys {
			index += 1

			pX = (coeX * (p - lminX)) + panLeft
			pY = (coeY * (lmaxY - values[index])) + panTop

			let dx = location.x - pX
			let dy = location.y - pY

			let distance = sqrt(dx * dx + dy * dy)
			if distance <= distance_min {
				distance_min = distance
				find = index
				balloonPoint = CGPoint(x: pX, y: pY)
				balloonValue = "\(NSString(format: "%.2f", values[find])) \(balloonUM)"
				let date = Date(timeIntervalSince1970: keys[find])
				let label = Chart.stringFromDate(date: date, format: balloonFormat) as NSString
				balloonDate = "\(label)"
			}
		}

		if  find != -1 && distance_min < 15.0 &&
			values[find] != Double.nan {
			let impactFeedbackgenerator = UIImpactFeedbackGenerator(style: .medium)
			impactFeedbackgenerator.prepare()
			impactFeedbackgenerator.impactOccurred()
			selected = find

			if self.balloonTimer != nil {
				self.balloonTimer?.invalidate()
				self.balloonTimer = nil
			}

			self.balloonTimer = Timer.scheduledTimer(
				timeInterval: 10,
				target: self,
				selector: #selector(self.unselect),
				userInfo: nil,
				repeats: false
			)
		} else {
			self.unselect()
		}

		delegate?.emitLongPress(from: self)
		self.setNeedsDisplay()
	}

	@objc func unselect() {
		selected = -1
		balloonPoint = nil
		balloonValue = nil
		balloonDate = nil
		if self.balloonTimer != nil {
			self.balloonTimer?.invalidate()
			self.balloonTimer = nil
		}
		setNeedsDisplay()
	}
	/// Replaces the current data with the provided points in **keys** and **values**. The provided
	/// vectors should have equal length. Else, the number of added points will be the size of the
	/// smallest vector.
	/// - Warning: If you can guarantee that the passed data points are sorted by **keys** in ascending order, you
	/// can set **alreadySorted** to true, to improve performance by saving a sorting run.
	func setData(keys: [Double], values: Array<Double>, alreadySorted: Bool = true) {
		self.alreadySorted = alreadySorted
		self.keys = keys.map { $0 }
		self.values = values.map { $0 }
		if self.keys.count < self.values.count {
			self.values.reserveCapacity(self.keys.count)
		} else if self.keys.count > self.values.count {
			self.keys.reserveCapacity(self.values.count)
		}
		setNeedsDisplay()
	}

	func clearData() {
		self.unselect()
		self.alreadySorted = true
		self.selected = -1
		self.keys.removeAll()
		self.values.removeAll()
		self.status.removeAll()
		setNeedsDisplay()
	}
	
	private func drawAxis() {
		//Draw X axis
		context?.move(to: CGPoint(x: panLeft, y: baserect!.maxY - panBottom))
		context?.addLine(to: CGPoint(x: baserect!.maxX - panRight, y: baserect!.maxY - panBottom))
		context?.setStrokeColor(axisColor.cgColor)
		context?.setLineDash(phase: 0, lengths: [])
		context?.strokePath()
	}

	/// Function draws ticks on vertical grid lines.
	private func drawGrids() {
		// Calcola la larghezza della viewport
		let totalWidth = baserect!.maxX - panRight - panLeft

		// Calcola le posizioni X in base alle differenze tra le keys
		var xPositions: [Double] = []
		var currentX: Double = 0.0

		for i in 0..<ticksX.count {
			if i > 0 {
				let distance = ticksX[i] - ticksX[i - 1]
				currentX += (totalWidth * (distance / (lmaxX - lminX))) // mappa la distanza sulla larghezza totale
			}
			xPositions.append(currentX + panLeft)
		}


		for i in 0 ..< ticksX.count {
			context?.move(to: CGPoint(x: xPositions[i], y: panTop))
			context?.addLine(to: CGPoint(x: xPositions[i], y: baserect!.maxY - panBottom))
		}

		context?.setStrokeColor(gridColor.cgColor)
		context?.setLineDash(phase: 0.0, lengths: dashLengths)
		context?.strokePath()
		context?.setLineDash(phase: 0, lengths: [])
	}

	/// Function draws ticks on vertical and horizontal axis.
	private func drawTickers() {
		// Calcola la larghezza della viewport
		let totalWidth = baserect!.maxX - panRight - panLeft

		// Calcola le posizioni X in base alle differenze tra le keys
		var xPositions: [Double] = []
		var currentX: Double = 0.0

		for i in 0..<ticksX.count {
			if i > 0 {
				let distance = ticksX[i] - ticksX[i - 1]
				currentX += (totalWidth * (distance / (lmaxX - lminX))) // mappa la distanza sulla larghezza totale
			}
			xPositions.append(currentX + panLeft)
		}
		context?.setTextDrawingMode(CGTextDrawingMode.fill)

		for i in 0 ..< ticksX.count {
			let date = Date(timeIntervalSince1970: ticksX[i])
			let label = Chart.stringFromDate(date: date, format: tickerFormat) as NSString
			let stringSize = label.size(withAttributes: tickerAttributes)
			label.draw(at: CGPoint(x: xPositions[i] - stringSize.width / 2.0,
								   y: baserect!.maxY - panBottom + 3.0), withAttributes: tickerAttributes)
			context?.move(to: CGPoint(x: xPositions[i], y: baserect!.maxY - panBottom))
			context?.addLine(to: CGPoint(x: xPositions[i], y: baserect!.maxY - panBottom + 5.0))
			context?.strokePath()
		}
		let coeY = (baserect!.maxY - panBottom - panTop) / (lmaxY - lminY)
		for i in 0 ..< ticksY.count {
			let label = NSString(format: "%5.0f", ticksY[i])
			let stringSize = label.size(withAttributes: tickerAttributes)
			label.draw(at: CGPoint(x: baserect!.maxX - panRight + 10.0,
								   y: (coeY * (lmaxY - ticksY[i])) + panTop - (stringSize.height / 2.0)), withAttributes: tickerAttributes)
		}
	}

	/// Function draws chart data lines.
	private func drawSurface() {
		let coeY = (baserect!.maxY - panBottom - panTop) / (lmaxY - lminY)
		var index = -1
		var pX: Double = 0.0
		var pY: Double = 0.0

		// Calcola la larghezza della viewport
		let totalWidth = baserect!.maxX - panRight - panLeft
		// Calcola le posizioni X in base alle differenze tra le keys
		var xPositions: [Double] = []
		var currentX: Double = 0.0

		for i in 0..<keys.count {
			if i > 0 {
				let distance = keys[i] - keys[i - 1]
				currentX += (totalWidth * (distance / (lmaxX - lminX))) // mappa la distanza sulla larghezza totale
			}
			xPositions.append(currentX + panLeft)
		}

		context!.saveGState()

		var path = UIBezierPath()
		path.lineWidth = 0.0

		lineColor.withAlphaComponent(0.2).setFill()
		var start = true
		var lastX = pX
		var lastY = pY
		var count = 0
		for _ in keys {
			index += 1

			pX = xPositions[index]

			if values[index].isNaN {
				if start == false {
					path.addLine(to: CGPoint(x: lastX, y: lastY))
					path.close()
					if count > 1 {
						path.fill()
					}
					count = 0
					path = UIBezierPath()
					path.lineWidth = 0.0
					start = true
				}

				continue
			}

			pY = (coeY * (lmaxY - values[index])) + panTop
			count += 1
			if start {
				var y = 0.0
				if (rangeY.lowerBound <= 0 && rangeY.upperBound >= 0) {
					y = (coeY * lmaxY) + panTop
				} else {
					y = (values[index] > 0) ? baserect!.maxY - panBottom : baserect!.minY + panTop
				}
				path.move(to: CGPoint(x: pX, y: y))
				path.addLine(to: CGPoint(x: pX, y: pY))
				start = false
			}

			if index == 0 {
				continue
			}

			if values[index - 1].isNaN == false {
				lastX = pX
				if (rangeY.lowerBound <= 0 && rangeY.upperBound >= 0) {
					lastY = (coeY * lmaxY) + panTop
				} else {
					lastY = (values[index] > 0) ? baserect!.maxY - panBottom : baserect!.minY + panTop
				}
				path.addLine(to: CGPointMake(pX, pY))
			}
		}

		if start == false {
			path.addLine(to: CGPoint(x: lastX, y: lastY))
			path.close()
			if count > 1 {
				path.fill()
			}
			path.addClip()
		}
		context!.restoreGState()

	}

	/// Function draws chart data lines.
	private func drawLines() {
		let coeY = (baserect!.maxY - panBottom - panTop) / (lmaxY - lminY)
		// Calcola la larghezza della viewport
		let totalWidth = baserect!.maxX - panRight - panLeft
		// Calcola le posizioni X in base alle differenze tra le keys
		var xPositions: [Double] = []
		var currentX: Double = 0.0

		for i in 0..<keys.count {
			if i > 0 {
				let distance = keys[i] - keys[i - 1]
				currentX += (totalWidth * (distance / (lmaxX - lminX))) // mappa la distanza sulla larghezza totale
			}
			xPositions.append(currentX + panLeft)
		}

		var index = -1
		var pX: Double = 0.0
		var pY: Double = 0.0

		for _ in keys {
			index += 1
			context?.move(to: CGPoint(x: pX, y: pY))
			pX = xPositions[index]

			if values[index].isNaN {
				continue
			}

			pY = (coeY * (lmaxY - values[index])) + panTop

			if index == 0 {
				continue
			}

			if status.count > index && status[index] && status[index - 1]   {
				context?.setStrokeColor(disabledColor.cgColor)
			}
			else {
				context?.setStrokeColor(lineColor.cgColor)
			}

			context?.setLineWidth(2.0)
			if values[index - 1].isNaN == false {
				context?.addLine(to: CGPoint(x: pX, y: pY))
				context?.strokePath()
			}
		}
		
	}

	/// Function draws a scatter for each data value.
	private func drawScatters() {
		let coeY = (baserect!.maxY - panBottom - panTop) / (lmaxY - lminY)

		// Calcola la larghezza della viewport
		let totalWidth = baserect!.maxX - panRight - panLeft

		// Calcola le posizioni X in base alle differenze tra le keys
		var xPositions: [Double] = []
		var currentX: Double = 0.0

		for i in 0..<keys.count {
			if i > 0 {
				let distance = keys[i] - keys[i - 1]
				currentX += (totalWidth * (distance / (lmaxX - lminX))) // mappa la distanza sulla larghezza totale
			}
			xPositions.append(currentX + panLeft)
		}

		for index in 0..<keys.count {
			let p = keys[index]

			if index >= values.count {
				break
			}

			if values[index].isNaN || p < lminX || p > lmaxX || values[index] < lminY || values[index] > lmaxY {
				continue
			}

			let pX = xPositions[index]
			let pY = (coeY * (lmaxY - values[index])) + panTop

			var radius = 12.0
			if index == selected {
				radius = 20.0
			}
			context?.setFillColor(status.count > index && status[index] == true ? disabledColor.cgColor : scatterColor.cgColor)
			context?.addEllipse(in: CGRect(origin: CGPoint(x: pX - (radius * screenScale), y: pY - (radius * screenScale)), size: CGSize(width: (radius * 2.0 * screenScale), height: (radius * 2.0 * screenScale))))
			context?.fillPath()
			context?.setFillColor(UIColor.white.cgColor)
			context?.addEllipse(in: CGRect(origin: CGPoint(x: pX - (radius * 0.5 * screenScale), y: pY - (radius * 0.5 * screenScale)), size: CGSize(width: (radius * screenScale), height: (radius * screenScale))))
			context?.fillPath()
		}
	}


	func drawBalloon(atPoint point: CGPoint, value: String, date: String) {
		let paragraphStyle = NSMutableParagraphStyle()
		paragraphStyle.alignment = .left

		let attributesValue = [
			NSAttributedString.Key.foregroundColor: UIColor.white,
			NSAttributedString.Key.font: UIFont.boldSystemFont(ofSize: 18),
			NSAttributedString.Key.paragraphStyle: paragraphStyle
		]

		let attributesDate = [
			NSAttributedString.Key.foregroundColor: UIColor.white,
			NSAttributedString.Key.font: UIFont.boldSystemFont(ofSize: 10),
			NSAttributedString.Key.paragraphStyle: paragraphStyle
		]

		let asvalue = NSAttributedString(string: value, attributes: attributesValue)
		let asdate = NSAttributedString(string: date, attributes: attributesDate)

		let bw = max(asvalue.size().width, asdate.size().width) + 10
		let bh = asvalue.size().height + asdate.size().height + 10
		var bx = point.x - (bw / 2.0)

		if bx < panLeft {
			bx = panLeft
		}
		if bx > baserect!.width - panRight - bw {
			bx = baserect!.width - panRight - bw
		}

		let by = baserect!.height - panBottom - 45

		let path = UIBezierPath(roundedRect: CGRect(x: bx, y: by, width: bw, height: bh), cornerRadius: 5)
		path.close()
		UIColor.black.withAlphaComponent(0.7).setFill()
		path.fill()

		asvalue.draw(in: CGRect(x: bx + 5, y: by + 5, width: bw - 10, height: asvalue.size().height))
		asdate.draw(in: CGRect(x: bx + 5, y: by + asvalue.size().height + 5, width: bw - 10, height: asdate.size().height))
	}

	func setRangeX(min: Double, max: Double) {
		if min < max {
			self.rangeX = min ... max
			generate(axis: 0)
		}
	}

	func setRangeY(min: Double, max: Double) {
		if min < max {
			self.rangeY = min ... max
			generate(axis: 1)
		}
	}

	func setStatus(_ status: Array<Bool>) {
		self.status = status
	}

	/// A convenience method which turns a Date object into a string like format you specified.
	/// - Note: The returned string is localized.
	/// - parameter date: The data to be converted.
	/// - parameter format: A format text. For the full reference of available format options,
	///   see Unicode Technical Reference (http://www.unicode.org/reports/tr35/tr35-dates.html#Date_Format_Patterns).
	/// - parameter timeZone: Time zone to use for conversion date.
	/// - returns: A string  matched with the format.
	static func stringFromDate(date: Date, format: String, timeZone: TimeZone? = .current) -> String {
		let df = DateFormatter()

		df.timeZone = timeZone
		df.dateFormat = format

		return df.string(from: date)
	}

	/// A convenience method which turns a Date object into a double value that corresponds to
	/// seconds since Epoch (1. Jan 1970, 00:00 UTC). This is the format used as axis coordinates by
	/// axis.
	/// - parameter date: The data to be converted.
	/// - returns: A double
	static func dateTimeToKey(date: Date) -> Double {
		return  date.timeIntervalSince1970
	}


	/// A convenience method which turns \a key (in seconds since Epoch 1. Jan 1970, 00:00 UTC) into a
	/// Date object. This can be used to turn axis coordinates to actual Date.
	///
	/// The accuracy achieved by this method is one millisecond
	/// \see dateTimeToKey
	///
	/// - parameter key: The key to be converted.
	/// - returns: A Date
	static func keyToDateTime(key: Double) -> Date {
		return Date(timeIntervalSince1970: TimeInterval(key))
	}

	private func generate(axis: UInt8) {
		switch axis {
		case 0:
			//X ticks
			tickStepX = getTickStepDate(range: rangeX)
			switch tickerTypeX {
			case .atNumeric:
				ticksX = createTickVector(tickStep: tickStepX, origin: tickOriginX, range: rangeX)
				trimTicks(range: rangeX, ticks: &ticksX, keepOneOutlier: false)
			case .atDate:
				ticksX = createTickVector(tickStep: tickStepX, origin: tickOriginX, range: rangeX, timeZone: TimeZone.current)
				trimTicks(range: rangeX, ticks: &ticksX, keepOneOutlier: false)
			}

			/* Avoid seg fault */
			if ticksX.isEmpty {
				return
			}

			lminX = ticksX.first!
			lmaxX = lminX + (Double(ticksX.count) * tickStepX)

		case 1:
			//Y ticks
			tickStepY = getTickStep(range: rangeY)
			switch tickerTypeY {
			case .atNumeric:
				ticksY = createTickVector(tickStep: tickStepY, origin: tickOriginY, range: rangeY)
				trimTicks(range: rangeY, ticks: &ticksY, keepOneOutlier: false)

			case .atDate:
				ticksY = createTickVector(tickStep: tickStepY, origin: tickOriginY, range: rangeY, timeZone: TimeZone.current)
				trimTicks(range: rangeY, ticks: &ticksY, keepOneOutlier: false)
				let isOriginInDST = TimeZone.current.isDaylightSavingTime(for: Chart.keyToDateTime(key: tickOriginY))

				for i in 0 ..< ticksY.count {
					let tickDateTime = Chart.keyToDateTime(key: ticksY[i])
					let isTickInDST = TimeZone.current.isDaylightSavingTime(for: tickDateTime)

					// Se c'è una differenza tra ora legale e solare, aggiusta l'orario
					if isOriginInDST != isTickInDST {
						// Aggiusta di un'ora avanti o indietro
						let timeAdjustment: TimeInterval = isTickInDST ? -3600 : 3600
						let adjustedDateTime = tickDateTime.addingTimeInterval(timeAdjustment)
						ticksY[i] = Chart.dateTimeToKey(date: adjustedDateTime)
					}
				}
			}



			/* Avoid seg fault */
			if ticksY.isEmpty {
				return
			}

			lminY = rangeY.lowerBound
			lmaxY = rangeY.upperBound

		default:
			break
		}




	}

	/// Returns the decimal mantissa of \a input. Optionally, if magnitude is not set to zero, it also
	///
	/// For example, an input of 142.6 will return a mantissa of 1.426 and a magnitude of 100.
	/// - parameter input: Input value
	/// - parameter magnitude: magnitude
	/// - returns: returns the magnitude of  input as a power of 10.
	private func getMantissa(input: Double, magnitude: inout Double?) -> Double {
		let mag = pow(10.0, floor(log10(input)))
		if magnitude != nil {
			magnitude = mag
		}
		return input / mag
	}


	/// Returns a number that is close to input but has a clean, easier human readable mantissa. How
	/// strongly the mantissa is altered, and thus how strong the result deviates from the original
	/// input
	/// - parameter input: Input value
	/// - returns: number
	private func cleanMantissa(input: Double) -> Double {
		var magnitude: Double? = Double()
		let mantissa: Double = getMantissa(input: input, magnitude: &magnitude)

		return pickClosest(target: mantissa, candidates: [1.0, 2.0, 2.5, 5.0, 10.0]) * magnitude!
	}

	/// Returns the coordinate contained in candidates which is closest to the provided target.
	/// - parameter target: Coordinate target.
	/// - parameter candidates: List of candidates
	/// - returns: Return the coordinate
	private func pickClosest(target: Double, candidates: [Double]) -> Double {
		if candidates.count == 1 {
			return candidates.first!
		}

		var index = 0
		for ele in candidates {
			if target < ele {
				break
			}
			index += 1
		}

		if index >= candidates.count {
			return candidates[index - 1]
		}

		if index == 0 {
			return candidates.first!
		}

		return (target - candidates[index - 1] < candidates[index] - target) ? candidates[index - 1] : candidates[index]

	}

	private func getTickStep(range: ClosedRange<Double>) -> Double {
		let exactStep = (range.upperBound - range.lowerBound) / (Double(self.tickCountY) + 1e-10) // mTickCount ticks on average, the small addition is to prevent jitter on exact integers
		return cleanMantissa(input:exactStep)
	}

	///Returns a sensible tick step with intervals appropriate for a date-time-display, such as weekly,
	///monthly, bi-monthly, etc.
	/// - Note: that this tick step isn't used exactly when generating the tick vector in
	/// createTickVector, but only as a guiding value requiring some correction for each individual tick
	/// interval. Otherwise this would lead to unintuitive date displays, e.g. jumping between first day
	/// in the month to the last day in the previous month from tick to tick, due to the non-uniform
	/// length of months. The same problem arises with leap years.
	private func getTickStepDate(range: ClosedRange<Double>) -> Double {
		var result = (range.upperBound - range.lowerBound) / (Double(self.tickCountX) + 1e-10) // mTickCount ticks on average, the small addition is to prevent jitter on exact integers
		dateStrategy = .dsNone; // leaving it at dsNone means tick coordinates will not be tuned in any special way in createTickVector
		// ideal tick step is below 1 second -> use normal clean mantissa algorithm in units of seconds
		if result < 1 {
			result = cleanMantissa(input:result)
		} else if result < 86400*30.4375*12 { // below a year
			result = pickClosest(target: result, candidates:[ 1.0, 2.5, 5.0, 10.0, 15.0, 30.0, 60.0, 2.5*60, 5.0*60, 10.0*60, 15.0*60, 30.0*60, 60.0*60, // second, minute, hour range
										   3600.0*2, 3600.0*3, 3600.0*6, 3600.0*12, 3600.0*24, // hour to day range
										   86400.0*2, 86400.0*5, 86400.0*7, 86400.0*14, 86400.0*30.4375, 86400.0*30.4375*2, 86400.0*30.4375*3, 86400.0*30.4375*6, 86400.0*30.4375*12]) // day, week, month range (avg. days per month includes leap years)
			if result > 86400*30.4375-1 { // month tick intervals or larger
				dateStrategy = .dsUniformDayInMonth
			} else if result > 3600*24-1 { // day tick intervals or larger
				dateStrategy = .dsUniformTimeInDay;
			}

		} else { // more than a year, go back to normal clean mantissa algorithm but in units of years
			let secondsPerYear: Double = 86400.0*30.4375*12 // average including leap years
			result = cleanMantissa(input:result/secondsPerYear) * secondsPerYear
			dateStrategy = .dsUniformDayInMonth;
		}

		return result
	}

	private func createTickVector(tickStep: Double, origin: Double, range: ClosedRange<Double>) -> [Double] {
		var result: [Double] = []
		let firstStep: Int64 = Int64(floor((range.lowerBound - origin) / tickStep))
		let lastStep: Int64 = Int64(ceil((range.upperBound - origin) / tickStep))
		var tickCount: Int64 = (lastStep - firstStep + 1)
		if tickCount < 0 {
			tickCount = 0
		}

		for i in 0 ..< tickCount {
			result.append(origin + Double((firstStep + i)) * tickStep)
		}

		return result
	}

	private func createTickVector(tickStep: Double, origin: Double, range: ClosedRange<Double>, timeZone: TimeZone) -> [Double] {
		var result: [Double] = createTickVector(tickStep: tickStep, origin: origin, range: range)

		if !result.isEmpty {
			var calendar = Calendar.current
			calendar.timeZone = timeZone
			var tickDateTime: Date

			if dateStrategy == .dsUniformTimeInDay {
				let uniformDateTime = Chart.keyToDateTime(key: origin) // the time of this datetime will be set for all other ticks, if possible

				for i in 0 ..< result.count {
					tickDateTime = Chart.keyToDateTime(key: result[i])
					if let updatedTickDateTime = calendar.date(bySettingHour: calendar.component(.hour, from: uniformDateTime),
															   minute: calendar.component(.minute, from: uniformDateTime),
															   second: calendar.component(.second, from: uniformDateTime),
															   of: tickDateTime) {
						result[i] = Chart.dateTimeToKey(date: updatedTickDateTime)
					}
				}
			} else if dateStrategy == .dsUniformDayInMonth {
				let uniformDateTime = Chart.keyToDateTime(key: origin) // this day (in month) and time will be set for all other ticks, if possible

				for i in 0 ..< result.count {
					tickDateTime = Chart.keyToDateTime(key: result[i])
					if calendar.date(bySettingHour: calendar.component(.hour, from: uniformDateTime),
									 minute: calendar.component(.minute, from: uniformDateTime),
									 second: calendar.component(.second, from: uniformDateTime),
									 of: tickDateTime) != nil {
						let range = calendar.range(of: .day, in: .month, for: tickDateTime)!
						let numDays = range.count
						let uniformDay = calendar.component(.day, from: uniformDateTime)
						let tickDay = calendar.component(.day, from: tickDateTime)
						let thisUniformDay : Int = uniformDay <= numDays ? uniformDay : numDays // don't exceed month (e.g. try to set day 31 in February)
						if thisUniformDay - tickDay < -15 { // with leap years involved, date month may jump backwards or forwards, and needs to be corrected before setting day
							tickDateTime = tickDateTime.addMonth(months: 1)!
						} else if thisUniformDay - tickDay > 15 { // with leap years involved, date month may jump backwards or forwards, and needs to be corrected before setting day
							tickDateTime = tickDateTime.addMonth(months: -1)!
						}
						tickDateTime = calendar.date(from: DateComponents(
							calendar: calendar,
							timeZone: timeZone,
							year: calendar.component(.year, from: tickDateTime),
							month: calendar.component(.month, from: tickDateTime),
							day: calendar.component(.day, from: uniformDateTime),
							hour: calendar.component(.hour, from: uniformDateTime),
							minute: calendar.component(.minute, from: uniformDateTime),
							second: calendar.component(.second, from: uniformDateTime)
						))!
						result[i] = Chart.dateTimeToKey(date: tickDateTime)
					}
				}
			}
		}

		// Remove duplicate values
		var temp: [Double] = []

		for i in 0 ..< result.count {
			let value = result[i]
			if !temp.contains(value) {
				temp.append(value)
			}
		}


		result = temp

		return result
	}


	private func trimTicks(range: ClosedRange<Double>, ticks: inout [Double], keepOneOutlier: Bool) {
		var lowFound: Bool = false
		var highFound: Bool = false
		var lowIndex = 0
		var highIndex = -1

		for i in 0 ..< ticks.count {
			if ticks[i] >= range.lowerBound {
				lowFound = true
				lowIndex = i
				break
			}
		}

		for i in stride(from: ticks.count - 1, to: 0, by: -1) {
			if ticks[i] <= range.upperBound {
				highFound = true
				highIndex = i
				break
			}
		}

		if highFound && lowFound {
			let trimFront = max(0, lowIndex - (keepOneOutlier ? 1 : 0))
			let trimBack = max(0, ticks.count - (keepOneOutlier ? 2 : 1) - highIndex)
			if trimFront > 0 || trimBack > 0 {
				let trim = ticks[trimFront ..< ticks.count - trimBack]
				ticks = Array(trim)
			}
			return
		}
		ticks = []
	}

}

extension Chart: UIGestureRecognizerDelegate {

	public func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
		if gestureRecognizer is UIPanGestureRecognizer && otherGestureRecognizer is UISwipeGestureRecognizer {
			let swipeGestureRecognizer = otherGestureRecognizer as! UISwipeGestureRecognizer


			let direction = swipeGestureRecognizer.direction
			if direction == .up || direction == .down {
				// Lo swipe è principalmente verticale, quindi non interferisce con il pan.
				return false
			}
		}

		return true
	}

}

extension Date {
	func addMonth(months: Int) -> Date? {
		return Calendar.current.date(byAdding: .month, value: months, to: self)
	}
}

func CGColorFromRGB(rgbValue: Int32) -> CGColor {
	let red : CGFloat = ((CGFloat)((rgbValue & 0xFF0000) >> 16)) / 255.0
	let green : CGFloat = ((CGFloat)((rgbValue & 0x00FF00) >> 8)) / 255.0
	let blue : CGFloat = ((CGFloat)((rgbValue & 0x00FF) >> 0)) / 255.0

	return CGColor(red: red, green: green, blue: blue, alpha: 1.0)
}



