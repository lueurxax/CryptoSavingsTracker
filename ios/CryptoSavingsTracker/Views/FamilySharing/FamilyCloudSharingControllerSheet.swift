//
//  FamilyCloudSharingControllerSheet.swift
//  CryptoSavingsTracker
//

#if os(iOS)
import SwiftUI
import UIKit
import CloudKit

struct FamilyCloudSharingControllerSheet: UIViewControllerRepresentable {
    let request: FamilyShareCloudSharingRequest
    let onDidSave: () -> Void
    let onDidFail: (String) -> Void
    let onDidStopSharing: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIViewController(context: Context) -> UICloudSharingController {
        let controller = UICloudSharingController(share: request.share, container: request.container)
        controller.delegate = context.coordinator
        controller.availablePermissions = [.allowPrivate, .allowReadOnly]
        return controller
    }

    func updateUIViewController(_ uiViewController: UICloudSharingController, context: Context) {
    }

    final class Coordinator: NSObject, UICloudSharingControllerDelegate {
        private let parent: FamilyCloudSharingControllerSheet

        init(parent: FamilyCloudSharingControllerSheet) {
            self.parent = parent
        }

        func cloudSharingController(_ csc: UICloudSharingController, failedToSaveShareWithError error: any Error) {
            parent.onDidFail(error.localizedDescription)
        }

        func itemTitle(for csc: UICloudSharingController) -> String? {
            parent.request.shareTitle
        }

        func cloudSharingControllerDidSaveShare(_ csc: UICloudSharingController) {
            parent.onDidSave()
        }

        func cloudSharingControllerDidStopSharing(_ csc: UICloudSharingController) {
            parent.onDidStopSharing()
        }
    }
}
#endif
