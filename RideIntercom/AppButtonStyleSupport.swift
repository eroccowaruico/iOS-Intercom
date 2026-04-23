import SwiftUI

extension View {
    func appProminentButtonStyle() -> some View {
        buttonStyle(.borderedProminent)
            .tint(AppColorPalette.buttonProminentBackground)
            .foregroundStyle(AppColorPalette.buttonProminentForeground)
    }

    func appCallCardStyle() -> some View {
        padding(AppSpacing.xl)
            .background(AppColorPalette.cardMaterial)
            .overlay(
                RoundedRectangle(cornerRadius: AppCornerRadius.card)
                    .stroke(AppColorPalette.cardBorder, lineWidth: AppBorderWidth.card)
            )
            .clipShape(RoundedRectangle(cornerRadius: AppCornerRadius.card))
    }

    func appDiagnosticsCardStyle() -> some View {
        padding(AppSpacing.xl)
            .background(AppColorPalette.diagnosticsCardMaterial)
            .overlay(
                RoundedRectangle(cornerRadius: AppCornerRadius.card)
                    .stroke(AppColorPalette.cardBorder, lineWidth: AppBorderWidth.card)
            )
            .clipShape(RoundedRectangle(cornerRadius: AppCornerRadius.card))
    }

    func appPanelCardStyle(borderColor: Color? = nil) -> some View {
        padding(AppSpacing.xl)
            .background(AppColorPalette.panelSurface)
            .overlay(
                RoundedRectangle(cornerRadius: AppCornerRadius.card)
                    .stroke(borderColor ?? AppColorPalette.cardBorder, lineWidth: AppBorderWidth.card)
            )
            .clipShape(RoundedRectangle(cornerRadius: AppCornerRadius.card))
    }

    func appStateToggleButtonTint(isActive: Bool) -> some View {
        tint(isActive ? AppColorPalette.danger : AppColorPalette.buttonProminentBackground)
    }
}
