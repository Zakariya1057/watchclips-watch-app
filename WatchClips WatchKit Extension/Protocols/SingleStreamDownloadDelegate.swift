//
//  SingleStreamDownloadDelegate.swift
//  WatchClips
//
//  Created by Zakariya Hassan on 21/12/2024.
//


import Foundation

/// Callback interface so your ViewModel can observe progress/completion/failures.
protocol SingleStreamDownloadDelegate: AnyObject {
    func downloadDidUpdate(remoteURL: URL, received: Int64, total: Int64)
    func downloadDidFinish(remoteURL: URL, localFile: URL?)
    func downloadDidFail(remoteURL: URL, error: Error)
}
