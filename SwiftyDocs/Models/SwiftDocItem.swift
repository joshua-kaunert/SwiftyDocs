//
//  OrganizedDocs.swift
//  SwiftyDocs
//
//  Created by Michael Redig on 7/2/19.
//  Copyright © 2019 Red_Egg Productions. All rights reserved.
//

import Foundation

/**
This is where the documentation data will spend most of its time. The data is first imported through the `InputDoc` struct before sitting here until it finally gets exported.

This data type is recursive and can contain children of the same type. As `SwiftDocItem` represents all entities from a class to class/struct properties to a global function and everything in between, it needs to be able to contain the items that descend from it. (A class's properties and methods, for example)
*/
class SwiftDocItem: Hashable, CustomStringConvertible, CustomDebugStringConvertible {

	/// The title of the doc item
	let title: String
	/// The access control of the doc item
	let accessControl: AccessControl
	/// If there is any documetation written for the doc item, it will go here.
	let comment: String?
	/// The file the doc item resides in. This is to help open source contributors to find where an item resides more quickly.
	let sourceFile: String
	/// The kind of the doc item. This is an enum primarily consisting of things like `class`, `enum`, `struct` and similar, but has an `other` option for situations that haven't been anticipated
	let kind: TypeKind
	/// If this item has any children (for example, a class might have properties or methods), this is where they will reside.
	let properties: [SwiftDocItem]?
	/// When an item created internally gets extended, it makes sense to group the extensions with the parent Type instead of on their own.
	var extensions: [SwiftDocItem] = []
	/// A list of attributes for the item. This will include things like `lazy`
	let attributes: [String]
	/// The code declaration of the item. This is not always rendered in an expected way, especially in the case of computed properties.
	var declaration: String {
		var declaration = parsedDeclaration ?? (docDeclaration ?? "no declaration")
		// unless it is lazy...
		if attributes.contains("lazy") {
			declaration = docDeclaration ?? (parsedDeclaration ?? "no declaration")
		}
		// double check that it's clean output
		return declaration.replacingOccurrences(of: ##"\s+=$"##, with: "", options: .regularExpression, range: nil)
	}

	private let docDeclaration: String?
	private let parsedDeclaration: String?

	/// The debug output string value
	var description: String {
		let properties = self.properties?.map { "\($0.title):\($0.kind)" }.joined(separator: " - ") ?? ""
		let extensions = self.extensions.map { "\($0.title):\($0.kind)" }.joined(separator: " - ")
		return """
		\(title) (\(accessControl.stringValue)) \(kind.stringValue)
			Properties: \(properties)
			Extensions: \(extensions)
		"""
	}

	var debugDescription: String {
		return description
	}

	/// Creates a new SwiftDocItem
	init(title: String, accessControl: AccessControl, comment: String?, sourceFile: String, kind: TypeKind, properties: [SwiftDocItem]?, attributes: [String], docDeclaration: String?, parsedDeclaration: String?) {
		self.title = title
		self.accessControl = accessControl
		self.comment = comment
		self.sourceFile = sourceFile
		self.kind = kind
		self.properties = properties
		self.attributes = attributes
		self.docDeclaration = docDeclaration
		self.parsedDeclaration = parsedDeclaration
	}

	/// A consistent, relative linking path used for html output. 
	func htmlLink(format: SaveFormat = .html, output: PageCount) -> String {
		let folderValue = kind.stringValue.capitalized.replacingNonWordCharacters()
		let link: String
		switch output {
		case .multiPage:
			let fileExt = format != .markdown ? "html" : "md"
			let fileName = title.replacingNonWordCharacters(lowercased: false) + "." + fileExt
			link = "\(folderValue)/\(fileName)"
		case .singlePage:
			link = "#\(title.replacingNonWordCharacters())"
		}

		return link
	}

	/// Equatable implementation
	static func ==(lhs: SwiftDocItem, rhs: SwiftDocItem) -> Bool {
		return lhs.title == rhs.title &&
			lhs.accessControl == rhs.accessControl &&
			lhs.comment == rhs.comment &&
			lhs.sourceFile == rhs.sourceFile &&
			lhs.kind == rhs.kind &&
			lhs.properties == rhs.properties &&
			lhs.attributes == rhs.attributes &&
			lhs.declaration == rhs.declaration
	}

	/// Generates the hash value for Hashable
	func hash(into hasher: inout Hasher) {
		hasher.combine(title)
		hasher.combine(accessControl)
		hasher.combine(comment)
		hasher.combine(sourceFile)
		hasher.combine(kind)
		hasher.combine(properties)
		hasher.combine(attributes)
		hasher.combine(declaration)
	}
}

/// Convenience initializers
extension SwiftDocItem {
	/// Creates a new SwiftDocItem with provided extensions. Also accepts a string for access control as opposed to an `AccessControl` enum.
	convenience init(title: String, accessControl acString: String, comment: String?, sourceFile: String, kind: TypeKind, properties: [SwiftDocItem]?, extensions: [SwiftDocItem], attributes: [String], docDeclaration: String?, parsedDeclaration: String?) {
		let accessControl = AccessControl.createFrom(string: acString)
		self.init(title: title, accessControl: accessControl, comment: comment, sourceFile: sourceFile, kind: kind, properties: properties, attributes: attributes, docDeclaration: docDeclaration, parsedDeclaration: parsedDeclaration)
		self.extensions = extensions
	}

	/// Creates a new SwiftDocItem with no extensions. Accepts a string for access control as opposed to an `AccessControl` enum.
	convenience init(title: String, accessControl acString: String, comment: String?, sourceFile: String, kind: TypeKind, properties: [SwiftDocItem]?, attributes: [String], docDeclaration: String?, parsedDeclaration: String?) {
		self.init(title: title, accessControl: acString, comment: comment, sourceFile: sourceFile, kind: kind, properties: properties, extensions: [], attributes: attributes, docDeclaration: docDeclaration, parsedDeclaration: parsedDeclaration)
	}
}
