// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "mentu-recipes",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "MentuRecipesCore", targets: ["MentuRecipesCore"]),
        .executable(name: "mentu-recipes", targets: ["mentu-recipes"])
    ],
    targets: [
        .target(name: "MentuRecipesCore"),
        .executableTarget(
            name: "mentu-recipes",
            dependencies: ["MentuRecipesCore"]
        ),
        .testTarget(
            name: "MentuRecipesCoreTests",
            dependencies: ["MentuRecipesCore"]
        )
    ],
    swiftLanguageModes: [.v5]
)
