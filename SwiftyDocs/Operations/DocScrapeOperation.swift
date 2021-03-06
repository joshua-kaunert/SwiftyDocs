//
//
//  Created by Michael Redig on 6/6/19.
//

import Foundation
import SourceKittenFramework

/// Technically this isn't necessary in this case. I'm just testing alternatives to what I'm used to for concurrency
class DocScrapeOperation: ConcurrentOperation {
	let path: String
	var jsonData: Data?

	init(path: String) {
		self.path = path
	}

	override func start() {
		state = .isExecuting

		let module = Module(xcodeBuildArguments: [], inPath: path)

		if let docs = module?.docs {
			let docString = docs.description

			jsonData = docString.data(using: .utf8)
		}
		state = .isFinished
	}
}
