import SwiftUI

struct PharmacyPin: View {
  let isSelected: Bool

  private var side: CGFloat { isSelected ? 42 : 28 }
  /// A square rotated 45° with three rounded corners reaches this far below its centre.
  private var height: CGFloat { side / 2 + side * 0.5.squareRoot() }

  var body: some View {
    ZStack(alignment: .top) {
      if isSelected {
        teardrop(side + 8).fill(Color.pinSelected)
          .frame(width: side + 8, height: side + 8)
          .rotationEffect(.degrees(45))
          .offset(y: -4)
      }
      teardrop(side)
        .fill(isSelected ? Color.pinSelected : Color.accentDefault)
        .overlay(teardrop(side).strokeBorder(Color.pinOutline, lineWidth: isSelected ? 3 : 2))
        .frame(width: side, height: side)
        .rotationEffect(.degrees(45))
      Image(systemName: "plus")
        .font(.system(size: side * 0.5, weight: .heavy))
        .foregroundStyle(Color.interactiveOnPrimary)
        .frame(width: side, height: side)
    }
    .frame(width: side, height: height, alignment: .top)
    .shadow(color: .black.opacity(0.25), radius: 1.5, y: 1)
    // Keep a 44-point hit target with the tip still at the bottom edge.
    .frame(
      width: max(minimumHitTarget, side), height: max(minimumHitTarget, height),
      alignment: .bottom
    )
    .contentShape(Rectangle())
  }

  private func teardrop(_ side: CGFloat) -> UnevenRoundedRectangle {
    UnevenRoundedRectangle(
      topLeadingRadius: side / 2, bottomLeadingRadius: side / 2, bottomTrailingRadius: 2,
      topTrailingRadius: side / 2)
  }
}

struct OriginMarker: View {
  var body: some View {
    ZStack {
      Circle().fill(Color.originMarker.opacity(0.22)).frame(width: 34, height: 34)
      Circle().fill(Color.originMarker).frame(width: 16, height: 16)
        .overlay(Circle().strokeBorder(Color.pinOutline, lineWidth: 3))
        .shadow(color: .black.opacity(0.25), radius: 1.5, y: 1)
    }
  }
}

#Preview {
  HStack(alignment: .bottom, spacing: 24) {
    PharmacyPin(isSelected: false)
    PharmacyPin(isSelected: true)
    OriginMarker()
  }
  .padding()
  .background(Color.pageBackground)
}
