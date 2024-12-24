# Chart Library

`Chart` is a customizable charting library for iOS and macOS built using Swift.

## Features
- Highly customizable chart visuals.
- Supports gestures like swipe and long-press.
- Easy to integrate using Swift Package Manager.

## Installation
Add this repository to your Swift Package Manager dependencies.

```swift
.package(url: "https://github.com/manux81/Chart.git", .upToNextMajor(from: "1.0.0"))
```

## Usage
```swift
import Chart

let chart = Chart(frame: .zero)
chart.setData(keys: [1, 2, 3], values: [10, 20, 30])
```

## License
This project is licensed under the MIT License. See the `LICENSE` file for more details.
