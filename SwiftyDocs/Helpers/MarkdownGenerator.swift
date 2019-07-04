//
//  MarkdownGenerator.swift
//  SwiftyDocs
//
//  Created by Michael Redig on 7/3/19.
//  Copyright © 2019 Red_Egg Productions. All rights reserved.
//

import Foundation

class MarkdownGenerator {

	func generateMarkdownDocumentString(fromRootDocItem swiftDocItem: SwiftDocItem, minimumAccessibility: Accessibility) -> String {
		let docHeader = "## \(swiftDocItem.title)"
		let type = "*\(swiftDocItem.kind.stringValue)*"
		let declaration = """
						```swift
						\(swiftDocItem.declaration)
						```
						"""
		let discussion = swiftDocItem.comment ?? "No documentation"

		var children = [String]()
		if let properties = swiftDocItem.properties {
			for property in properties {
				guard property.accessibility >= minimumAccessibility else { continue }
				let propTitle = "* **\(property.title)**"
				let propType = "*\(property.kind.stringValue)*"
				let propInfo = (property.comment ?? "No documentation")
				let propDeclaration =  """
							```swift
							\(property.declaration)
							```
							"""

				let outDown = "\(propTitle)\n\(propType)\n\n\(propDeclaration)\n\n\(propInfo)"

				children.append(outDown)
			}
		}

		var markdownOut = "\(docHeader)\n\(type)\n\(declaration)\n\n\(discussion)\n\n\((children.isEmpty ? "" : "___\n#### Members\n\n"))"

		for child in children {
			markdownOut += "\(child.replacingOccurrences(of: "\n", with: "\n\t"))\n\n"
		}

		return markdownOut
	}

	enum LinkStyle {
		case singlePage
		case multiPage
	}
	func generateMarkdownIndex(fromTopLevelIndex topLevelIndex: [SwiftDocItem], minimumAccessibility: Accessibility, linkStyle: LinkStyle) -> String {

		var markOut = ""
		var links = ""
		var currentTitle = ""
		for (index, item) in (topLevelIndex.sorted { $0.kind.stringValue < $1.kind.stringValue }).enumerated() {
			guard item.accessibility >= minimumAccessibility else { continue }
			if currentTitle != item.kind.stringValue.capitalized {
				currentTitle = item.kind.stringValue.capitalized
				markOut += currentTitle.isEmpty ? "" : "\n"
				markOut += "#### \(currentTitle)\n\n"
			}
			let charSet = CharacterSet(charactersIn: "(:)").inverted
			markOut += "* [\(item.title)][\(index)]\n"
			switch linkStyle {
			case .singlePage:
				let linkValue = item.title.replacingNonWordCharacters()
				links += "[\(index)]:#\(linkValue)\n"
			case .multiPage:
				let linkValue = item.title.replacingNonWordCharacters(lowercased: false)
				let folderValue = currentTitle.replacingNonWordCharacters()
				links += "[\(index)]:\(folderValue)/\(linkValue).html\n"
			}
		}

		return markOut + "\n\n" + links
	}
}

extension String {
	func replacingNonWordCharacters(lowercased: Bool = true) -> String {
		var rVal = self
		if lowercased {
			rVal = rVal.lowercased()
		}
		return rVal.replacingOccurrences(of: ##"\W+"##, with: "-", options: .regularExpression, range: nil)
	}
}
