// swift-tools-version:5.3
import PackageDescription

let package = Package(
	name: "Chart",
	platforms: [
		.iOS(.v13)
	],
	products: [
		.library(
			name: "Chart",
			targets: ["Chart"]),
	],
	targets: [
		.target(
			name: "Chart",
			dependencies: []),
		.testTarget(
			name: "ChartTests",
			dependencies: ["Chart"]),
	]
)
