#if canImport(UIKit) && !os(watchOS) // iOS and visionOS: watchOS has UIKit but lacks APIs this group of views uses
import SwiftUI
import DingsKit

/// Spec-driven credential form for registry providers (everything after
/// the first two hand-built providers): renders one input per `CredentialFieldSpec`, the
/// provider's key-creation steps, and — for beta integrations — a "help us
/// verify" note with the support address. Pushed from onboarding's provider
/// chooser and presented from Settings' Connections section.
public struct ProviderSetupView: View {
    @Bindable var model: ProviderConnectionModel
    var onConnected: () -> Void
    /// Whether this view pops/dismisses itself via the environment
    /// `dismiss()` action right before calling `onConnected`. Defaults to
    /// `true`, matching every caller that just wants to go back to whatever
    /// presented this screen once connected.
    ///
    /// Pass `false` when `onConnected` itself needs to keep navigating on
    /// the *same* `NavigationPath` this view was pushed on (for example,
    /// pushing a follow-up onboarding step). `dismiss()`'s pop is not
    /// synchronous: it resolves as its own animated transition well after
    /// this button's action returns, so a `NavigationPath` mutation made
    /// before that transition finishes races it. The path's logical value
    /// still converges to what you'd expect, but `NavigationStack` renders
    /// the surviving destination as an empty screen, confirmed by
    /// instrumenting a real reproduction, not by inspection. Callers that
    /// pass `false` must pop this view themselves (as part of the same
    /// `onConnected` handler) instead of relying on this dismiss.
    var dismissesOnConnect: Bool = true

    public init(
        model: ProviderConnectionModel,
        onConnected: @escaping () -> Void = {},
        dismissesOnConnect: Bool = true
    ) {
        self.model = model
        self.onConnected = onConnected
        self.dismissesOnConnect = dismissesOnConnect
    }

    @State private var revealedFields: Set<String> = []
    @Environment(\.openURL) private var openURL
    @Environment(\.dismiss) private var dismiss

    private var spec: ProviderSpec { model.spec }

    public var body: some View {
        Form {
            Section {
                Text(verbatim: "\(Dings.config.appName) \(spec.setupIntro)")
                    .font(.callout)
            }

            Section {
                ForEach(Array(spec.fields.enumerated()), id: \.element.id) { index, field in
                    fieldRow(field, position: index)
                }
            } header: {
                Text(spec.credentialsHeader)
            } footer: {
                Text(spec.credentialsFooter)
            }

            if case .invalid(let message) = model.state {
                Section {
                    Label(message, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red).font(.callout)
                }
            }

            Section {
                Button {
                    Task {
                        await model.validateAndSave {
                            if dismissesOnConnect { dismiss() }
                            onConnected()
                        }
                    }
                } label: {
                    if model.state == .validating { HStack { ProgressView(); Text(coreLocalized("Connecting…")) } }
                    else { Text(coreLocalized("Save & Connect")) }
                }
                .disabled(model.incomplete || model.state == .validating)
                .accessibilityIdentifier("setup.\(spec.provider.rawValue)SaveConnect")
            }

            Section {
                Button {
                    guard let url = URL(string: spec.instructionsURL) else { return }
                    openURL(url)
                    Log.app.debug("setup: opening \(url.host ?? "")\(url.path) in Safari")
                } label: {
                    Label(spec.instructionsLinkTitle, systemImage: "safari")
                }
                .accessibilityIdentifier("setup.open\(spec.provider.rawValue)")
            } header: {
                Text(spec.credentialsSourceHeader)
            } footer: {
                Text(spec.credentialsSourceFooter)
            }

            Section(coreLocalized("Steps")) {
                ForEach(Array(spec.instructionSteps.enumerated()), id: \.offset) { index, step in
                    Label(step, systemImage: "\(index + 1).circle")
                }
            }

            if spec.isBeta, let supportEmail = Dings.config.supportEmail {
                // One quiet line. The ask already lives on the beta screen that
                // pushed here; repeating the whole explanation on the form reads as
                // a warning label, and there is nothing to warn about.
                Section {
                    Label {
                        Text(coreLocalized("Once it's connected, tell us at \(supportEmail) whether the readings look right."))
                            .font(.footnote)
                    } icon: {
                        Image(systemName: "testtube.2").foregroundStyle(.orange)
                    }
                }
            }
        }
        .navigationTitle(spec.provider.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .task { model.load() }
    }

    @ViewBuilder
    private func fieldRow(_ field: CredentialFieldSpec, position: Int) -> some View {
        let binding = Binding(
            get: { model.values[field.id, default: ""] },
            set: { model.values[field.id] = $0 }
        )
        HStack {
            Group {
                if !field.isSecure || revealedFields.contains(field.id) {
                    TextField(field.label, text: binding)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                } else {
                    SecureField(field.label, text: binding)
                }
            }
            .textContentType(AutoFill.contentType(at: position, of: spec.fields.count))
            .accessibilityIdentifier("setup.\(spec.provider.rawValue).\(field.id)")
            if field.isSecure {
                Button {
                    if revealedFields.contains(field.id) { revealedFields.remove(field.id) }
                    else { revealedFields.insert(field.id) }
                } label: {
                    Image(systemName: revealedFields.contains(field.id) ? "eye.slash" : "eye")
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(revealedFields.contains(field.id)
                                    ? coreLocalized("Hide \(field.label)")
                                    : coreLocalized("Show \(field.label)"))
            }
            PasteButton(payloadType: String.self) { items in
                if let s = items.first { model.values[field.id] = s.trimmingCharacters(in: .whitespacesAndNewlines) }
            }.labelStyle(.iconOnly)
        }
    }
}
#endif
