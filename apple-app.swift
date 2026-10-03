import SwiftUI

// ============================================================
// AppleStyleWindowOverlay.swift
//
// A reusable macOS window/content overlay designed to give
// custom software a more distinctly Apple-like appearance.
//
// Features:
// • Native macOS materials
// • Ultra-subtle window borders
// • Adaptive light/dark appearance
// • Soft depth
// • Rounded content surfaces
// • Apple-style toolbar
// • Sidebar / content separation
// • Hover effects
// ============================================================

@available(macOS 13.0, *)
struct AppleWindowSurface<Content: View>: View {

    @Environment(\.colorScheme)
    private var colorScheme

    let title: String
    let content: Content

    init(
        title: String,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.content = content()
    }

    var body: some View {

        VStack(spacing: 0) {

            AppleToolbar(
                title: title
            )

            Divider()
                .opacity(0.35)

            content
                .frame(maxWidth: .infinity,
                       maxHeight: .infinity)
        }
        .background(
            WindowMaterial()
        )
        .clipShape(
            RoundedRectangle(
                cornerRadius: 12,
                style: .continuous
            )
        )
        .overlay(
            RoundedRectangle(
                cornerRadius: 12,
                style: .continuous
            )
            .stroke(
                BorderColour(
                    colorScheme: colorScheme
                ),
                lineWidth: 0.75
            )
        )
        .shadow(
            color:
                Color.black.opacity(
                    colorScheme == .dark
                    ? 0.35
                    : 0.16
                ),
            radius: 20,
            x: 0,
            y: 8
        )
        .padding(10)
    }
}

// ============================================================
// Window material
// ============================================================

@available(macOS 13.0, *)
private struct WindowMaterial: View {

    @Environment(\.colorScheme)
    private var colorScheme

    var body: some View {

        Rectangle()
            .fill(
                .ultraThinMaterial
            )
            .background(
                colorScheme == .dark
                ? Color.black.opacity(0.08)
                : Color.white.opacity(0.08)
            )
    }
}

// ============================================================
// Apple-style toolbar
// ============================================================

@available(macOS 13.0, *)
struct AppleToolbar: View {

    let title: String

    var body: some View {

        HStack(spacing: 12) {

            // Traffic-light breathing space
            Color.clear
                .frame(width: 68)

            Text(title)
                .font(
                    .system(
                        size: 13,
                        weight: .semibold
                    )
                )
                .foregroundStyle(
                    .primary
                )

            Spacer()

            ToolbarIcon(
                systemName: "sidebar.left"
            )

            ToolbarIcon(
                systemName: "ellipsis.circle"
            )

            ToolbarIcon(
                systemName: "magnifyingglass"
            )
        }
        .padding(.horizontal, 16)
        .frame(height: 44)
    }
}

// ============================================================
// Toolbar button
// ============================================================

@available(macOS 13.0, *)
struct ToolbarIcon: View {

    let systemName: String

    @State private var hovering = false

    var body: some View {

        Image(
            systemName: systemName
        )
        .font(
            .system(
                size: 13,
                weight: .medium
            )
        )
        .frame(
            width: 28,
            height: 28
        )
        .background(
            hovering
            ? Color.primary.opacity(0.08)
            : Color.clear
        )
        .clipShape(
            RoundedRectangle(
                cornerRadius: 7,
                style: .continuous
            )
        )
        .onHover {
            hovering = $0
        }
        .animation(
            .easeOut(duration: 0.12),
            value: hovering
        )
    }
}

// ============================================================
// Adaptive border
// ============================================================

private func BorderColour(
    colorScheme: ColorScheme
) -> Color {

    if colorScheme == .dark {

        return Color.white.opacity(
            0.12
        )

    } else {

        return Color.black.opacity(
            0.10
        )
    }
}



@available(macOS 13.0, *)
struct AppleApplicationView: View {

    var body: some View {

        AppleWindowSurface(
            title: "Northbridge"
        ) {

            HStack(spacing: 0) {

                AppleSidebar()

                Divider()
                    .opacity(0.3)

                MainContent()
            }
        }
        .frame(
            minWidth: 900,
            minHeight: 600
        )
    }
}




@available(macOS 13.0, *)
struct AppleSidebar: View {

    @State private var selection = 0

    var body: some View {

        VStack(
            alignment: .leading,
            spacing: 4
        ) {

            SidebarItem(
                title: "Overview",
                icon: "square.grid.2x2",
                selected: selection == 0
            ) {
                selection = 0
            }

            SidebarItem(
                title: "Projects",
                icon: "folder",
                selected: selection == 1
            ) {
                selection = 1
            }

            SidebarItem(
                title: "Activity",
                icon: "chart.line.uptrend.xyaxis",
                selected: selection == 2
            ) {
                selection = 2
            }

            SidebarItem(
                title: "Settings",
                icon: "gearshape",
                selected: selection == 3
            ) {
                selection = 3
            }

            Spacer()
        }
        .padding(10)
        .frame(width: 190)
    }
}

@available(macOS 13.0, *)
struct SidebarItem: View {

    let title: String
    let icon: String
    let selected: Bool
    let action: () -> Void

    @State private var hovering = false

    var body: some View {

        Button(action: action) {

            HStack(spacing: 9) {

                Image(
                    systemName: icon
                )
                .frame(width: 18)

                Text(title)

                Spacer()
            }
            .font(
                .system(
                    size: 13,
                    weight:
                        selected
                        ? .semibold
                        : .regular
                )
            )
            .padding(
                .horizontal,
                10
            )
            .frame(height: 32)
            .background(

                selected
                ? Color.accentColor
                    .opacity(0.14)

                : hovering
                ? Color.primary
                    .opacity(0.06)

                : Color.clear
            )
            .clipShape(
                RoundedRectangle(
                    cornerRadius: 7,
                    style: .continuous
                )
            )
        }
        .buttonStyle(.plain)
        .onHover {
            hovering = $0
        }
    }
}

