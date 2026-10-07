import SwiftUI
import TasteTraceAPI
import TasteTraceUI

#if canImport(UIKit)
import PhotosUI
import UIKit
#endif

/// The three ways to add a food: photograph it, scan it, or type it.
///
/// The barcode tile is deliberately disabled rather than tappable. A button that
/// opens an apology is worse than one that plainly says it is not ready, and
/// leaving the scanner out also keeps the camera permission wording honest.
struct MealInputMethodCard: View {
    @Bindable var model: LogMealViewModel
    /// Moves the keyboard into the name field, which is the third option.
    var focusTyping: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("How would you like to add it?")
                .font(TTFont.caption)
                .foregroundStyle(TTColor.textSecondary)

            HStack(spacing: 8) {
                #if canImport(UIKit)
                SecondaryButton("Photo", systemImage: "camera") {
                    model.photoKind = .meal
                    model.showPhotoSheet = true
                }
                .disabled(model.isAnalyzingPhoto)
                #endif

                SecondaryButton("Barcode", systemImage: "barcode.viewfinder") {}
                    .disabled(true)
                    .overlay(alignment: .topTrailing) {
                        StatusBadge("Soon", tone: .info).offset(x: 6, y: -8)
                    }

                SecondaryButton("Type it", systemImage: "pencil", action: focusTyping)
            }

            if model.isAnalyzingPhoto {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Reading your photo…")
                        .font(TTFont.caption)
                        .foregroundStyle(TTColor.textSecondary)
                }
            }

            if let message = model.photoError {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundStyle(TTColor.warning)
                    Text(message)
                        .font(TTFont.caption)
                        .foregroundStyle(TTColor.textSecondary)
                    Spacer(minLength: 0)
                    Button("Dismiss") { model.dismissPhotoError() }
                        .font(TTFont.caption)
                        .foregroundStyle(TTColor.primary)
                        .buttonStyle(.plain)
                }
            }
        }
    }
}

#if canImport(UIKit)

/// Picks a photo, prepares it, and hands it to the view model.
struct MealPhotoSheet: View {
    @Bindable var model: LogMealViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var pickerItem: PhotosPickerItem?
    @State private var showCamera = false
    @State private var problem: String?

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                Picker("What does the photo show?", selection: $model.photoKind) {
                    Text("A meal").tag(MealPhotoKind.meal)
                    Text("An ingredient label").tag(MealPhotoKind.label)
                }
                .pickerStyle(.segmented)

                Text(model.photoKind == .meal
                     ? "Photograph the plate. You'll get a name and an ingredient list to check before anything is logged."
                     : "Photograph the printed ingredient list on the packaging.")
                    .font(TTFont.caption)
                    .foregroundStyle(TTColor.textSecondary)

                VStack(spacing: 10) {
                    Button { showCamera = true } label: {
                        Label("Take a photo", systemImage: "camera")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)

                    PhotosPicker(selection: $pickerItem, matching: .images, photoLibrary: .shared()) {
                        Label("Choose from library", systemImage: "photo.on.rectangle")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }

                if let problem {
                    Text(problem).font(TTFont.caption).foregroundStyle(TTColor.danger)
                }

                Text("The photo is read and then discarded. It is never saved.")
                    .font(TTFont.caption)
                    .foregroundStyle(TTColor.textSecondary)

                Spacer()
            }
            .padding(20)
            .background(TTColor.background)
            .navigationTitle("Add from a photo")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .sheet(isPresented: $showCamera) {
                CameraPicker { image in
                    showCamera = false
                    Task { await send(image) }
                }
            }
            .onChange(of: pickerItem) { _, item in
                guard let item else { return }
                Task {
                    guard
                        let data = try? await item.loadTransferable(type: Data.self),
                        let image = UIImage(data: data)
                    else {
                        problem = "That image couldn't be opened. Try another."
                        return
                    }
                    await send(image)
                }
            }
        }
    }

    private func send(_ image: UIImage) async {
        guard let jpeg = MealPhotoEncoding.jpeg(from: image) else {
            problem = "That image couldn't be prepared. Try another."
            return
        }
        problem = nil
        await model.recognize(jpeg: jpeg, kind: model.photoKind)
        // A success navigates onward and closes this; a failure leaves the sheet
        // up with the reason on the card behind it.
        if model.photoError != nil { dismiss() }
    }
}

/// The system camera. UIImagePickerController because SwiftUI has no camera of
/// its own, and the modern library picker needs no permission string while this
/// does: NSCameraUsageDescription, declared in ios/project.yml.
struct CameraPicker: UIViewControllerRepresentable {
    let onCapture: (UIImage) -> Void

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let controller = UIImagePickerController()
        controller.sourceType = .camera
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ controller: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onCapture: onCapture) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let onCapture: (UIImage) -> Void
        init(onCapture: @escaping (UIImage) -> Void) { self.onCapture = onCapture }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            if let image = info[.originalImage] as? UIImage { onCapture(image) }
            picker.dismiss(animated: true)
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            picker.dismiss(animated: true)
        }
    }
}

#endif
