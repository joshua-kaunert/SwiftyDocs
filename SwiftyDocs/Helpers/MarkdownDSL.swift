//
//  MarkdownDSL.swift
//  SwiftyDocs
//
//  Created by Michael Redig on 7/7/19.
//  Copyright © 2019 Red_Egg Productions. All rights reserved.
//

import Foundation

/**
A markdown DSL. I'm not sure if it is entirely necessary, but it was fun to make! I may eventually spin this out into its own framework, but for now I'll leave it as is.

Link handling is a bit of a hack. If someone can design a better pattern, have at it!

Perhaps the root node could be a struct - dedicated append function and might properly handle links?
*/
public enum MDNode: CustomStringConvertible {
	public enum MDAttribute {
		case indentation(Int)
		case linkURL(URL)
		case newlinePrefix(Int)
	}

	public enum MDType {
		case inline
		case block
	}

	// make sure this is an inline value
	public var description: String {
		let rendered = render(inlineLinks: true)
		return rendered.text.trimmingCharacters(in: .whitespacesAndNewlines)
	}

	/// This is a HACK. It's BAD!
	/// You cannot juggle multiple documents at the same time - they all need to be done sequentially!
	static var linkCache = Set<URL>()

	var type: MDType? {
		if case .element(_, let type, _, _) = self {
			return type
		}
		return nil
	}

	var text: String? {
		if case .element(let text, _, _, _) = self {
			return text
		}
		return nil
	}

	func finalRender(inlineLinks: Bool = false) -> String {
		let tuple = render(inlineLinks: inlineLinks)
		let links = MDNode.linkCache.map { "[\($0.hashValue)]:\($0)" }.joined(separator: "\n")
		MDNode.linkCache.removeAll()

		return tuple.text + "\n" + links
	}

	func render(inheritedIndentation: Int = 0, parent: MDNode? = nil, inlineLinks: Bool = false) -> (text: String, links: [URL]) {
		switch self {
		case .element(let text, let type, let attrs, let children):
			var rVal = text

			var links = attrs.getLinks()
			if links.count == 1 {
				if inlineLinks {
					rVal += "(\(links[0].absoluteString))"
					links.removeAll()
				} else {
					rVal += "[\(links[0].hashValue)]"
				}
			}


			let additionalIndentation = "\t".repeated(count: attrs.getIndentation())
			rVal = "\(additionalIndentation)\(rVal)"
			rVal = rVal.replacingOccurrences(of: "\n", with: "\n\(additionalIndentation + "\t".repeated(count: inheritedIndentation))", options: .regularExpression, range: nil)
			if type == .block {
				rVal += "\n"
			}

			let childRender = children?.render(inheritedIndentation: inheritedIndentation + 1, parent: self, inlineLinks: inlineLinks)
			rVal += childRender?.text ?? ""
			links += childRender?.links ?? []
			return (rVal, links)

		case .indentedCollection(let nodes):
			var rVal = ""
			var links = [URL]()
			for node in nodes {
				let rendered = node.render(inheritedIndentation: inheritedIndentation, parent: self)
				if rVal.last == "\n" || rVal.isEmpty {
					rVal += "\t".repeated(count: inheritedIndentation)
				}
				rVal += rendered.text
				links += rendered.links
			}
			return (rVal, links)

		case .nonIndentedCollection(let nodes):
			var rVal = ""
			var links = [URL]()
			for node in nodes {
				let rendered = node.render(inheritedIndentation: inheritedIndentation, parent: self)

				// in the event that there are consecutive list items, remove excess lines between them
				if rendered.text.hasPrefix("* ") || rendered.text.hasPrefix("1. ") {
					if let lastValue = lastValue(in: rVal),
						lastValue.hasPrefix("* ") || lastValue.hasPrefix("1. ")	{
						rVal = removeTrailingWhitespace(in: rVal)
						rVal += "\n"
					}
				}
				rVal += rendered.text + "\n"
				links += rendered.links
			}
			return (rVal, links)
		}
	}

	private func lastValue(in string: String) -> String? {
		let lines = string.split(separator: "\n")
		return lines.last?.trimmingCharacters(in: .whitespacesAndNewlines)
	}

	private func removeTrailingWhitespace(in string: String) -> String {
		return string.replacingOccurrences(of: ##"\s+$"##, with: "", options: .regularExpression, range: nil)
	}

	indirect case element(String, MDType, [MDAttribute], MDNode?)
	case nonIndentedCollection([MDNode])
	case indentedCollection([MDNode])
}

extension Array where Element == MDNode.MDAttribute {
	public func getLinks() -> [URL] {
		return self.reduce([URL]()) {
			if case .linkURL(let url) = $1 {
				return $0 + [url]
			}
			return $0
		}
	}

	public func getIndentation() -> Int {
		return self.reduce(0) {
			if case .indentation(let value) = $1 {
				return $0 + value
			}
			return $0
		}
	}
}

extension MDNode {
	public static func document(_ children: MDNode...) -> MDNode {
		return nonIndentedCollection(children)
	}

	public static func element(_ value: String, _ type: MDType, attributes: [MDAttribute], _ child: MDNode?) -> MDNode {
		return .element(String(describing: value), type, attributes, child)
	}

	public static func header(_ headerValue: Int, _ text: String) -> MDNode {
		let headerValue = min(max(headerValue, 1), 6)
		let hashTags = "#".repeated(count: headerValue)
		return .element("\(hashTags) \(text)", .block, attributes: [], nil)
	}

	public static func paragraph(_ text: String, indentation: Int = 0) -> MDNode {
		return .element(text, .block, [.indentation(indentation)], nil)
	}

	public static func paragraphWithInlineElements(_ elements: [MDNode], indentation: Int = 0) -> MDNode {
		let value = elements.map { $0.render().text }.joined(separator: " ")
		return .element(value, .block, [.indentation(indentation)], nil)
	}

	public static func text(_ text: String, indentation: Int = 0) -> MDNode {
		return .element(text, .inline, [.indentation(indentation)], nil)
	}

	public static func unorderedListItem(_ text: String, _ children: MDNode ..., indentation: Int = 0) -> MDNode {
		return .element("* \(text)", .block, [.indentation(indentation)], .indentedCollection(children))
	}

	public static func orderedListItem(_ text: String, _ children: MDNode ..., indentation: Int = 0) -> MDNode {
		return .element("1. \(text)", .block, [.indentation(indentation)], .indentedCollection(children))
	}

	public static func codeBlock(_ text: String, syntax: String = "", indentation: Int = 0) -> MDNode {
		return .element("```\(syntax)\n\(text)\n```", .block, [.indentation(indentation)], nil)
	}

	public static func codeInline(_ text: String) -> MDNode {
		return .element("`\(text)`", .inline, [], nil)
	}

	public static func link(_ text: String, _ destination: String) -> MDNode {
		let url = URL(string: destination) ?? URL(string: "#")!
		MDNode.linkCache.insert(url)
		return .element("[\(text)]", .inline, [.linkURL(url)], nil)
	}

	public static func italics(_ text: String) -> MDNode {
		return .element("*\(text)*", .inline, [], nil)
	}

	public static func bold(_ text: String) -> MDNode {
		return .element("**\(text)**", .inline, [], nil)
	}

	public static func boldItalics(_ text: String) -> MDNode {
		return .element("***\(text)***", .inline, [], nil)
	}

	public static func newline() -> MDNode {
		return .element("\n", .inline, [], nil)
	}

	public static func hr() -> MDNode {
		return .element("___", .block, [], nil)
	}

	public func appending(nodes: [MDNode]) -> MDNode {
		switch self {
		case .nonIndentedCollection(let existingNodes):
			return .nonIndentedCollection(existingNodes + nodes)
		case .indentedCollection(let existingNodes):
			return .indentedCollection(existingNodes + nodes)
		case .element(let text, let type, let attrs, let child):
			let newChild: MDNode
			if let child = child {
				newChild = child.appending(nodes: nodes)
			} else {
				newChild = .indentedCollection(nodes)
			}
			return .element(text, type, attrs, newChild)
		}
	}

	public func appending(node: MDNode) -> MDNode {
		return self.appending(nodes: [node])
	}
}

/// this is witchcraft... Nothing is implemented!
extension MDNode.MDAttribute: Equatable {}

extension MDNode: Equatable {
	public static func ==(lhs: MDNode, rhs: MDNode) -> Bool {
		switch lhs {
		case .element(let text, let type, let attr, let child):
			if case .element(let rText, let rType, let rAttr, let rChild) = rhs {
				return text == rText &&
					type == rType &&
					attr == rAttr &&
					child == rChild
			}
		case .indentedCollection(let children):
			if case .indentedCollection(let rChildren) = rhs {
				return children == rChildren
			}
		case .nonIndentedCollection(let children):
			if case .nonIndentedCollection(let rChildren) = rhs {
				return children == rChildren
			}
		}
		return false
	}
}
