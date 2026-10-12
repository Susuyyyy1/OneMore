import SwiftUI
import UIKit

/// 揉皱后摊平的米色纸张背景。图片由 tools/make-paper.swift 生成（浅色/深色两张），
/// 放在 Assets 的 Paper 里；想调整褶皱程度改脚本参数后重新生成即可。
struct PaperBackground: View {
    var body: some View {
        ZStack {
            Theme.paper
            Image("Paper")
                .resizable()
                .scaledToFill()
        }
        .ignoresSafeArea()
    }
}

/// 列表/表单的每一行用玻璃材质
struct GlassRowBackground: View {
    var body: some View {
        Rectangle()
            .fill(.clear)
            .glassEffect(.regular.tint(Theme.glassTint), in: .rect)
    }
}

/// 纸张背景 + 玻璃行的 List
struct PaperList<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        List {
            Group { content }
                .listRowBackground(GlassRowBackground())
                .listRowSeparatorTint(Theme.ink.opacity(0.12))
        }
        .scrollContentBackground(.hidden)
        .background(PaperBackground())
    }
}

/// 纸张背景 + 玻璃行的 Form
struct PaperForm<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        Form {
            Group { content }
                .listRowBackground(GlassRowBackground())
                .listRowSeparatorTint(Theme.ink.opacity(0.12))
        }
        .scrollContentBackground(.hidden)
        .background(PaperBackground())
    }
}

extension View {
    /// 玻璃卡片
    func glassCard(cornerRadius: CGFloat = 22) -> some View {
        glassEffect(.regular.tint(Theme.glassTint), in: .rect(cornerRadius: cornerRadius))
    }

    /// 米色的主按钮（玻璃）
    func beigeGlassButton() -> some View {
        buttonStyle(.glassProminent).tint(Theme.beigeButton).foregroundStyle(Theme.onBeige)
    }
}

enum Appearance {
    /// 导航栏大标题用衬线字体和墨色，更像纸质笔记本
    static func apply() {
        let ink = UIColor(Theme.ink)
        func serif(_ style: UIFont.TextStyle, weight: UIFont.Weight) -> UIFont {
            let base = UIFont.preferredFont(forTextStyle: style)
            let descriptor = UIFont.systemFont(ofSize: base.pointSize, weight: weight).fontDescriptor.withDesign(.serif)
                ?? base.fontDescriptor
            return UIFont(descriptor: descriptor, size: base.pointSize)
        }
        let nav = UINavigationBar.appearance()
        nav.largeTitleTextAttributes = [.foregroundColor: ink, .font: serif(.largeTitle, weight: .bold)]
        nav.titleTextAttributes = [.foregroundColor: ink, .font: serif(.headline, weight: .semibold)]
    }
}
