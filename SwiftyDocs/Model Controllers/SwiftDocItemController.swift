//
//  SortedDocController.swift
//  SwiftyDocs
//
//  Created by Michael Redig on 7/3/19.
//  Copyright © 2019 Red_Egg Productions. All rights reserved.
//

import Foundation

/**
The primary brains of this software. This contains the collection of `SwiftDocItems` and performs logic related to exporting as well.
*/
class SwiftDocItemController {

	// MARK: - properties
	private var _docs: [SwiftDocItem] = []
	/// The source of truth for all the doc items
	private(set) var docs: [SwiftDocItem] = [] // {
//		get {
//			return _docs
//		}
//		set {
//			_docs = mergeInternalExtensions(in: newValue)
//		}
//	}

	/// All classes
	var classesIndex: [SwiftDocItem] {
		return search(forTitle: nil, ofKind: .class, withMinimumAccessControl: .private)
	}
	/// All structs
	var structsIndex: [SwiftDocItem] {
		return search(forTitle: nil, ofKind: .struct, withMinimumAccessControl: .private)
	}
	/// All enums
	var enumsIndex: [SwiftDocItem] {
		return search(forTitle: nil, ofKind: .enum, withMinimumAccessControl: .private)
	}
	/// All protocols
	var protocolsIndex: [SwiftDocItem] {
		return search(forTitle: nil, ofKind: .protocol, withMinimumAccessControl: .private)
	}
	/// All extensions
	var extensionsIndex: [SwiftDocItem] {
		return search(forTitle: nil, ofKind: .extension, withMinimumAccessControl: .private)
	}
	/// All global functions
	var globalFuncsIndex: [SwiftDocItem] {
		return search(forTitle: nil, ofKind: .globalFunc, withMinimumAccessControl: .private)
	}
	/// All type aliases
	var typealiasIndex: [SwiftDocItem] {
		return search(forTitle: nil, ofKind: .typealias, withMinimumAccessControl: .private)
	}

	/// All items accessible globally
	var topLevelIndex: [SwiftDocItem] {
		return classesIndex + structsIndex + enumsIndex + protocolsIndex + extensionsIndex + globalFuncsIndex + typealiasIndex
	}
	/// All items accesible globally, but only access control greater than or equal to that chosen by `minimumAccessControl`
	var toplevelIndexMinAccess: [SwiftDocItem] {
		return topLevelIndex.filter { $0.accessControl >= minimumAccessControl }
	}

	/// The lowest access control items that should be output. For example, when set to internal, many functions will ignore anything set to fileprivate or private, but include everything else. Defaults to internal.
	var minimumAccessControl = AccessControl.internal

	/// The URL of the project selected for output
	var projectURL: URL?
	/// The URL of the directory the selected project resides in
	var projectDirectoryURL: URL? {
		return projectURL?.deletingLastPathComponent()
	}
	/**
	The URL of the first page that should be shown when using a separated file output. It prioritizes a markdown file titled "doclandingpage.md", so that users may customize the first thing their users encounter when viewing documentation. It falls back to any variation of capitalization for a `Readme.md` file, then to a `Readme` file. If none of these exist, no landing page is included in the exported documentation.

	The term "Landing Page" is used to disambiguate between the role of an `index.html` file and an index, conceptually. Where an index usually contains a listing of all items contained within, but an `index.html` is simply the default page output when nothing specific is requested. The `index.html` file in this case needs to either be the actual documentation (in the case of single file output) or a page gluing the list of contents to the actual documentation (in the case of the multifile output). As these two roles are very distinguished, but their terms overlap, the need to disambiguate is necessary.
	*/
	var projectLandingPageURL: URL? {
		guard let directoryURL = projectDirectoryURL else { return nil }
		do {
			let contents = try FileManager.default.contentsOfDirectory(atPath: directoryURL.path)
			let lcContents: [(original: String, lowercase: String)] = contents.map { ($0, $0.lowercased()) }
			let landingPage = lcContents.first { (original: String, lowercase: String) -> Bool in
				let exists = lowercase == "doclandingpage.md"
				return exists
			}
			let readmeMarkdown = lcContents.first { (original: String, lowercase: String) -> Bool in
				let exists = lowercase == "readme.md"
				return exists
			}
			let readmeNoMarkdown = lcContents.first { (original: String, lowercase: String) -> Bool in
				let exists = lowercase == "readme"
				return exists
			}

			if let landingPage = landingPage {
				return directoryURL.appendingPathComponent(landingPage.original)
			}
			if let readmeMarkdown = readmeMarkdown {
				return directoryURL.appendingPathComponent(readmeMarkdown.original)
			}
			if let readmeNoMarkdown = readmeNoMarkdown {
				return directoryURL.appendingPathComponent(readmeNoMarkdown.original)
			}

		} catch {
			NSLog("Error getting project directory files: \(error)")
		}
		return nil
	}

	private var _projectTitle: String?
	/// Stores the title of the project. This is used for headers in the exported files and a default name implementation when saving the export.
	var projectTitle: String {
		get {
			return _projectTitle ?? (projectURL?.deletingPathExtension().lastPathComponent ?? "Documentation")
		}
		set {
			_projectTitle = newValue
			if newValue.isEmpty {
				_projectTitle = nil
			}
		}
	}

	private let markdownGenerator = MarkdownGenerator()
	private let htmlWrapper = HTMLWrapper()
	private let fm = FileManager.default

	private let scrapeQueue: OperationQueue = {
		let queue = OperationQueue()
		queue.name = UUID().uuidString
		return queue
	}()

	// MARK: - inits

	/**
	Initializes a new SwiftDocItemController
	*/
	init() {}

	// MARK: - CRUD
	/**
	Accepts an array of `DocFile`s as input and, after converting them to a `SwiftDocItem`, adds them to the `docs` array.
	*/
	func add(docs: [DocFile]) {
		for doc in docs {
			add(doc: doc)
		}
	}

	/**
	Adds a single `DocFile`, after converting it to a `SwiftDocItem`, to the `docs` array
	*/
	func add(doc: DocFile) {
		guard let items = getDocItemsFrom(containers: doc.topLevelContainers,
										  sourceFile: doc.filePath?.path ?? "")
																else { return }
		docs.append(contentsOf: items)
	}

	/**
	Removes all items from the `docs` array.
	*/
	func clear() {
		docs.removeAll()
	}

	/**
	Given an array of `DocFile`s, converts them to the `SwiftDocItem` format and returns an optional array of `SwiftDocItem`s. Recurses through every `DocFile`'s children and converts those as well, but instead of adding them to the array, it instead sets them as children of the `SwiftDocItem` they descend from.
	*/
	private func getDocItemsFrom(containers: [DocFile.DocContainer]?, sourceFile: String, parentName: String = "") -> [SwiftDocItem]? {
		guard let containers = containers else { return nil }

		var sourceFile = sourceFile
		if let projectDir = projectDirectoryURL {
			let baseDir = projectDir.path
			sourceFile = sourceFile.replacingOccurrences(of: baseDir, with: "")
				.replacingOccurrences(of: ##"^\/"##, with: "", options: .regularExpression, range: nil)
		}

		var items = [SwiftDocItem]()
		for container in containers {
			let kind = TypeKind.createFrom(string: container.kind)

			// special case for enum cases
			if case .other(let value) = kind, value == "enum case" {
				guard let newArrayWrappedItem = getDocItemsFrom(containers: container.nestedContainers,
																sourceFile: sourceFile,
																parentName: parentName)
																else { continue }
				items += newArrayWrappedItem
				continue
			}

			guard let name = container.name,
				let accessControl = container.accessControl
				else { continue }

			// recursively get all children
			let children = getDocItemsFrom(containers: container.nestedContainers, sourceFile: sourceFile, parentName: name)

			let newTitle: String
			switch kind {
			case .other(_):
				newTitle = name
			default:
				newTitle = parentName.isEmpty ? name : parentName + "." + name
			}

			let strAttributes = container.attributes?.map { $0.name } ?? []

			let newItem = SwiftDocItem(title: newTitle,
									   accessControl: accessControl,
									   comment: container.comment,
									   sourceFile: sourceFile,
									   kind: kind,
									   properties: children,
									   attributes: strAttributes,
									   docDeclaration: container.docDeclaration,
									   parsedDeclaration: container.parsedDeclaration)
			items.append(newItem)
		}
		return items
	}

	/**
	Searches for extensions on internal Types and merges them into the Type.
	*/
	private func mergeInternalExtensions(in docs: [SwiftDocItem]) -> [SwiftDocItem] {
		var docs = docs
		var indicies = [Int]()
		for (extIndex, anExtension) in docs.enumerated() where anExtension.kind == .extension {
			for anObject in docs.enumeratedChildren() where anObject.kind == .class || anObject.kind == .enum || anObject.kind == .protocol || anObject.kind == .struct {
				if anObject.title == anExtension.title {
					anObject.extensions.append(anExtension)
					indicies.append(extIndex)
				}
			}
		}

		indicies.reversed().forEach { docs.remove(at: $0) }

		return docs
	}

	/// Consolidates extensions on types external to the project with multiple implementations into one SwiftDocItem. Need to figure out how to do.
	private func mergeExternalExtensions(in docs: [SwiftDocItem]) -> [SwiftDocItem] {
		var docs = docs
		// do a pass finding extensions on top level - save to set/array
		let extensionTitles = docs
						.filter { $0.kind == .extension }
						.reduce(into: Set<String>()) { $0.insert($1.title) }
		// do a second pass removing them into a temp array/set/merging
		var extensionGroups = [SwiftDocItem]()
		for extensionTitle in extensionTitles {
			var extensionGroup: SwiftDocItem?
			while let extensionIndex = docs.lastIndex(where: { $0.title == extensionTitle && $0.kind == .extension }) {
				if extensionGroup == nil {
					extensionGroup = SwiftDocItem(title: extensionTitle, accessControl: .open, comment: "The following are extensions on the \(extensionTitle) Type.", sourceFile: projectTitle, kind: .extension, properties: nil, attributes: [], docDeclaration: nil, parsedDeclaration: nil)
				}
				extensionGroup?.extensions.append(docs[extensionIndex])
				docs.remove(at: extensionIndex)
			}
			guard let unwrappedExtensionGroup = extensionGroup else { continue }
			extensionGroups.append(unwrappedExtensionGroup)
		}
		// append them back to docs
		docs.append(contentsOf: extensionGroups)

		return docs
	}

	/**
	Given a directory URL containing an Xcode Project, gets the doc output from SourceKitten, converts it from JSON -> `DocFile` -> `SwiftDocItem` -> adds to the `docs` array.
	*/
	func getDocs(from projectDirectory: URL, completion: @escaping () -> Void) {

		let buildPath = projectDirectory.appendingPathComponent("build")
		let buildDirAlreadyExists = FileManager.default.fileExists(atPath: buildPath.path)
		let docScrapeOp = DocScrapeOperation(path: projectDirectory.path)
		let docFilesOp = BlockOperation { [weak self] in
			defer {
				if let self = self {
					self.docs = self.mergeInternalExtensions(in: self.docs)
					self.docs = self.mergeExternalExtensions(in: self.docs)
				}
				completion()
			}
			guard let data = docScrapeOp.jsonData else { return }

			do {
				let rootDocs = try JSONDecoder().decode([[String: DocFile]].self, from: data)
				let docs = rootDocs.flatMap { dict -> [DocFile] in
					var flatArray = [DocFile]()
					for (key, doc) in dict {
						var doc = doc
						doc.filePath = URL(fileURLWithPath: key)
						flatArray.append(doc)
					}
					return flatArray
				}
				self?.add(docs: docs)
			} catch {
				NSLog("Error decoding docs: \(error)")
				return
			}
		}
		let cleanupOp = BlockOperation {
			if !buildDirAlreadyExists {
				do {
					try FileManager.default.removeItem(at: buildPath)
				} catch {
					NSLog("Error deleting temp build directory: \(error)")
				}
			}
		}

		docFilesOp.addDependency(docScrapeOp)
		cleanupOp.addDependency(docScrapeOp)
		scrapeQueue.addOperations([docScrapeOp, docFilesOp, cleanupOp], waitUntilFinished: false)
	}

	/**
	Searches all the docs for matching parameters. Powers the computed properties above, but could also be utilized for user input, if such a feature was desired.
	*/
	func search(forTitle title: String?, ofKind kind: TypeKind?, withMinimumAccessControl minimumAccessControl: AccessControl = .internal) -> [SwiftDocItem] {
		var searchResults = docs.enumeratedChildren().filter { $0.accessControl >= minimumAccessControl }

		if let title = title {
			let titleLC = title.lowercased()
			searchResults = searchResults.filter { $0.title.lowercased().contains(titleLC) }
		}

		if let kind = kind {
			searchResults = searchResults.filter { $0.kind == kind }
		}

		return searchResults
	}

	// MARK: - Saving

	/**
	Initiates saving at the given path (`URL`) with the given style (`PageCount`) and format (`SaveFormat`).
	*/
	func save(with style: PageCount, to path: URL, in format: SaveFormat) {
		switch style {
		case .multiPage:
			saveMultifile(to: path, format: format)
		case .singlePage:
			saveSingleFile(to: path, format: format)
		}
	}

	/**
	Initiates saving a single file in a given format. The format consists of a generated index at the top of the file, with each additional entry appended to the end. The HTML formatted output also includes css and js to assist in rendering the documentation nicely.
	*/
	private func saveSingleFile(to path: URL, format: SaveFormat) {
		guard format != .docset else {
			saveDocset(to: path)
			return
		}

		let index = markdownContents(with: .singlePage, in: format)
		var text = toplevelIndexMinAccess.map { markdownPage(for: $0) }.joined(separator: "\n\n\n")
		text = index + "\n\n" + text
		if format == .html {
			text = text.replacingOccurrences(of: ##"</div>"##, with: ##"<\/div>"##)
			text = htmlWrapper.wrapInHTML(markdownString: text, withTitle: projectTitle, cssFile: "stylesDocs", dependenciesUpDir: false)
		}

		var outPath = path
		switch format {
		case .html:
			saveDependencyPackage(to: outPath, linkStyle: .singlePage)
			outPath.appendPathComponent("index")
			outPath.appendPathExtension("html")
		case .markdown:
			outPath.appendPathExtension("md")
		case .docset:
			// not possible to happen, but switch needs to be exhaustive
			break
		}

		do {
			try text.write(to: outPath, atomically: true, encoding: .utf8)
		} catch {
			NSLog("Failed to save file: \(error)")
		}
	}

	/**
	Initiates saving multiple files in a given format. The format consists of a generated index file for navigation, generates a landing page based on readme files present (see `projectLandingPageURL`), and generates an individual file for each major entry. The HTML formatted output also includes css and js to assist in rendering the documentation nicely.
	*/
	private func saveMultifile(to path: URL, format: SaveFormat) {
		var contents = markdownContents(with: .multiPage, in: format)
		var landingPageContents = getLandingPageContents()

		saveDependencyPackage(to: path, linkStyle: .multiPage)

		let fileExt = format == .html ? "html" : "md"

		// save all doc files
		toplevelIndexMinAccess.forEach {
			var markdown = markdownPage(for: $0)
			if format == .html {
				markdown = sanitizeForHTMLEmbedding(string: markdown)
				markdown = htmlWrapper.wrapInHTML(markdownString: markdown, withTitle: $0.title, cssFile: "stylesDocs", dependenciesUpDir: true)
			}
			let outPath = path
				.appendingPathComponent($0.kind.stringValue.replacingNonWordCharacters())
				.appendingPathComponent($0.title.replacingNonWordCharacters(lowercased: false))
				.appendingPathExtension(fileExt)
			do {
				try markdown.write(to: outPath, atomically: true, encoding: .utf8)
			} catch {
				NSLog("Failed writing file: \(error)")
			}
		}
		// save contents/index file
		do {
			let landingPageURL = path
				.appendingPathComponent("doclandingpage")
				.appendingPathExtension(fileExt)
			let indexURL = path
				.appendingPathComponent("index")
				.appendingPathExtension(fileExt)
			let contentsURL = path
				.appendingPathComponent("contents")
				.appendingPathExtension(fileExt)
			if format == .html {
				contents = sanitizeForHTMLEmbedding(string: contents)
				contents = htmlWrapper.wrapInHTML(markdownString: contents, withTitle: projectTitle, cssFile: "stylesContents", dependenciesUpDir: false)
				landingPageContents = sanitizeForHTMLEmbedding(string: landingPageContents)
				landingPageContents = htmlWrapper.wrapInHTML(markdownString: landingPageContents, withTitle: projectTitle, cssFile: "stylesDocs", dependenciesUpDir: false)
				let index = htmlWrapper.generateIndexPage(titled: projectTitle)
				try index.write(to: indexURL, atomically: true, encoding: .utf8)
			}
			try contents.write(to: contentsURL, atomically: true, encoding: .utf8)
			try landingPageContents.write(to: landingPageURL, atomically: true, encoding: .utf8)

		} catch {
			NSLog("Failed writing file: \(error)")
		}
	}

	/**
	Initiates saving a docset to a given path (`URL`). The format is identical to the multiple html files, just with some additional metadata like a SQLite index and Info.plist file.
	*/
	private func saveDocset(to path: URL) {
		let packageDir = path.path.hasSuffix(".docset") ? path : path.appendingPathExtension("docset")
		let contentsDir = packageDir.appendingPathComponent("Contents")
		let infoPlistURL = contentsDir.appendingPathComponent("Info.plist")
		let resourcesDir = contentsDir.appendingPathComponent("Resources")
		let sqlIndex = resourcesDir.appendingPathComponent("docSet.dsidx")
		let docsDir = resourcesDir.appendingPathComponent("Documents")

		do {
			try fm.createDirectory(atPath: docsDir.path, withIntermediateDirectories: true, attributes: nil)
		} catch {
			NSLog("There was an error creating the docset directories: \(error)")
		}
		saveMultifile(to: docsDir, format: .html)

		let infoPlistData = createInfoPlist()
		do {
			try infoPlistData.write(to: infoPlistURL)
		} catch {
			NSLog("There was an error writing the Info.plist: \(error)")
		}

		do {
			let sqlController = try SQLController(at: sqlIndex)

			let rows = getSQLInfoForRows()
			for row in rows {
				sqlController.addRow(with: row.name, type: row.type, path: row.path)
			}
		} catch {
			NSLog("There was an error creating the SQL Index: \(error)")
		}
	}

	/**
	Gathers contents for the landing page to be used in multifile exports.
	*/
	private func getLandingPageContents() -> String {
		guard let landingPageURL = projectLandingPageURL else { return "" }
		let contents = (try? String(contentsOf: landingPageURL)) ?? ""
		return contents
	}

	/**
	Saves all css and js required for proper html rendering in the path requested.
	*/
	func saveDependencyPackage(to path: URL, linkStyle: PageCount) {
		guard var jsURLs = Bundle.main.urls(forResourcesWithExtension: "js", subdirectory: nil, localization: nil) else { return }
		guard let maps = Bundle.main.urls(forResourcesWithExtension: "map", subdirectory: nil, localization: nil) else { return }
		jsURLs += maps

		guard let cssURLs = Bundle.main.urls(forResourcesWithExtension: "css", subdirectory: nil, localization: nil) else { return }

		let subdirs: [String]
		switch linkStyle {
		case .multiPage:
			subdirs = (TypeKind.topLevelCases.map { $0.stringValue }
				.joined(separator: "-") + "-css-js")
				.split(separator: "-")
				.map { String($0).replacingNonWordCharacters() }
		case .singlePage:
			subdirs = "css js"
				.split(separator: " ")
				.map { String($0) }
		}

		let subdirURLs = [path] + subdirs.map { path.appendingPathComponent($0) }

		do {
			if fm.fileExists(atPath: path.path) {
				try fm.removeItem(at: path)
			}
		} catch {
			NSLog("Error overwriting previous export: \(error)")
		}
		create(subdirectories: subdirURLs)
		copy(urls: jsURLs, to: path.appendingPathComponent("js"))
		copy(urls: cssURLs, to: path.appendingPathComponent("css"))

		let otherFiles = "localhost.webloc startLocalServer.command Instructions.md"
			.split(separator: " ")
			.map { String($0) }
			.map { Bundle.main.url(forResource: $0, withExtension: nil) }
			.compactMap { $0 }
		copy(urls: otherFiles, to: path)
	}

	/**
	Given a list of urls, creates a directory at each url, creating intermediate directories if they don't already exist.
	*/
	private func create(subdirectories: [URL]) {
		for subdirURL in subdirectories {
			do {
				try fm.createDirectory(atPath: subdirURL.path, withIntermediateDirectories: true, attributes: nil)
			} catch {
				NSLog("Error creating subdirectory: \(error)")
			}
		}
	}
	/**
	Copies files from an array of urls to a destination directory url.
	*/
	private func copy(urls: [URL], to destination: URL) {
		for url in urls {
			do {
				try fm.copyItem(at: url, to: destination.appendingPathComponent(url.lastPathComponent))
			} catch {
				NSLog("Error copying package file: \(error)")
			}
		}
	}

	/**
	Extracts the name, type, and path for each top level item to be passed into the SQLite index generator
	*/
	private func getSQLInfoForRows() -> [(name: String, type: String, path: String)] {
		var rows: [(name: String, type: String, path: String)] = []

		var currentTitle = ""

		for item in (topLevelIndex.sorted { $0.kind.stringValue < $1.kind.stringValue }) {
			guard item.accessControl >= minimumAccessControl else { continue }
			if currentTitle != item.kind.stringValue.capitalized {
				currentTitle = item.kind.stringValue.capitalized
			}

			let name = item.title
			let type = item.kind.docSetType
			let path = item.htmlLink(output: .multiPage)
			rows.append((name, type, path))
		}

		return rows
	}

	// MARK: - info plist generation

	/**
	Generates an Info.plist for the docset format
	*/
	private func createInfoPlist() -> Data {
		let cleanProjectTitle = projectTitle.replacingNonWordCharacters()

		let infoPlist = InfoPlistModel(bundleID: "com.swiftdocs.\(cleanProjectTitle)",
									bundleName: projectTitle,
									platformFamily: cleanProjectTitle.lowercased(),
									dashIndexFilePath: "doclandingpage.html",
									dashDocSetFamily: "dashtoc")

		let encoder = PropertyListEncoder()
		do {
			let data = try encoder.encode(infoPlist)
			return data
		} catch {
			NSLog("Error creating info.plist: \(error)")
		}

		return Data()
	}

	// MARK: - Markdown Generation

	/**
	Generates a markdown document for a given SwiftDocItem.
	*/
	func markdownPage(for doc: SwiftDocItem) -> String {
		return markdownGenerator.generateMarkdownDocumentString(fromRootDocItem: doc, minimumAccessControl: minimumAccessControl)
	}

	/**
	Generates an contents page in markdown format for all top level `SwiftDocItem`s.
	*/
	func markdownContents(with linkStyle: PageCount, in format: SaveFormat) -> String {
		return markdownGenerator.generateMarkdownContents(fromTopLevelIndex: topLevelIndex,
													   minimumAccessControl: minimumAccessControl,
													   linkStyle: linkStyle,
													   format: format)
	}

	/**
	Converts special characters common to both markdown, html, and swift to percent escaped values from a given string so that they don't interfere with the rendering of the final output.
	*/
	func sanitizeForHTMLEmbedding(string: String) -> String {
		var rVal = string.replacingOccurrences(of: ##"</div>"##, with: ##"<\/div>"##)

		let allowedSet = CharacterSet(charactersIn: "<>?_").inverted
		rVal = rVal.addingPercentEncoding(withAllowedCharacters: allowedSet) ?? rVal

		return rVal
	}
}
