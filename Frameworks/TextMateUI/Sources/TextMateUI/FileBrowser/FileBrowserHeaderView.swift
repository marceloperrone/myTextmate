import SwiftUI

// MARK: - File Browser Header View

/// Replaces OFBHeaderView — back/forward buttons and breadcrumb path popup.
public struct FileBrowserHeaderView: View {
    @Bindable var navigation: NavigationModel

    public init(navigation: NavigationModel) {
        self.navigation = navigation
    }

    public var body: some View {
        HStack(spacing: 4) {
            // Back button
            Button {
                navigation.goBack()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 12, weight: .medium))
            }
            .buttonStyle(.borderless)
            .disabled(!navigation.canGoBack)
            .help("Go Back")

            // Forward button
            Button {
                navigation.goForward()
            } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .medium))
            }
            .buttonStyle(.borderless)
            .disabled(!navigation.canGoForward)
            .help("Go Forward")

            Spacer(minLength: 4)

            // Breadcrumb path menu
            Menu {
                ForEach(navigation.breadcrumbs) { crumb in
                    Button(crumb.name) {
                        navigation.navigateTo(crumb.url)
                    }
                }

                Divider()

                Button("Computer") {
                    navigation.goToComputer()
                }
                Button("Home") {
                    navigation.goHome()
                }
            } label: {
                HStack(spacing: 4) {
                    Image(nsImage: NSWorkspace.shared.icon(forFile: navigation.currentURL.path))
                        .resizable()
                        .frame(width: 14, height: 14)

                    Text(navigation.currentURL.lastPathComponent.isEmpty ? "/" : navigation.currentURL.lastPathComponent)
                        .font(.system(size: 11, weight: .medium))
                        .lineLimit(1)
                        .truncationMode(.middle)

                    Image(systemName: "chevron.down")
                        .font(.system(size: 8))
                        .foregroundStyle(.secondary)
                }
            }
            .menuStyle(.borderlessButton)
            .frame(maxWidth: .infinity)

            Spacer(minLength: 4)

            // Go to parent
            Button {
                navigation.goToParent()
            } label: {
                Image(systemName: "arrow.up")
                    .font(.system(size: 12, weight: .medium))
            }
            .buttonStyle(.borderless)
            .help("Go to Enclosing Folder")
        }
        .padding(.horizontal, 8)
        .frame(height: 28)
        .background(.bar)
    }
}
