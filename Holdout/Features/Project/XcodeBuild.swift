//
//  XcodeBuild.swift
//  Holdout
//

import Foundation

/// The result of the most recent Xcode build, read from DerivedData's build logs.
struct XcodeBuild: Equatable {
    let project: String
    let workspace: URL?
    let finishedAt: Date
    let succeeded: Bool
    let errors: Int
    let warnings: Int
}
