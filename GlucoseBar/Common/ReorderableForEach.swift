//
//  ReorderableForEach.swift
//  GlucoseBar
//
//  Created by Andreas Stokholm on 2025-06-27.
//

import SwiftUI
import UniformTypeIdentifiers

public struct ReorderableForEach<Data, Content>: View
where Data : Hashable, Content : View {
  @Binding var data: [Data]
  private let content: (Data, Bool) -> Content

  @State private var draggedItem: Data?
  @State private var hasChangedLocation: Bool = false

  public init(_ data: Binding<[Data]>,
              @ViewBuilder content: @escaping (Data, Bool) -> Content) {
    _data = data
    self.content = content
  }

  public var body: some View {
    ForEach(data, id: \.self) { item in
        content(item, hasChangedLocation && draggedItem == item)
          .onDrag {
            draggedItem = item
              return NSItemProvider(object: "\(item.hashValue)" as NSString)
          }
//          preview: {
/// TODO: (as) This image shuldn't be in the preview, but instead replace the actual item, not having a preview at all is what we want
//              Image(systemName: "arrowtriangle.right.and.line.vertical.and.arrowtriangle.left.fill").foregroundStyle(.blue)
//              Text("")
//          }
        /// TODO: (as) How do we make this .onDrop sit on the calling function instead of here? Can we "export" the delegate and call into it properly somehow? Or do we skip this helper file to build it straight in to the top level view?
          .onDrop(of: [UTType.plainText], delegate: ReorderDropDelegate(
            item: item,
            data: $data,
            draggedItem: $draggedItem,
            hasChangedLocation: $hasChangedLocation))
//          .opacity(draggedItem == item ? 0 : 1)
    }
  }

  struct ReorderDropDelegate<InnerData>: DropDelegate
  where InnerData : Equatable {
    let item: InnerData
    @Binding var data: [InnerData]
    @Binding var draggedItem: InnerData?
    @Binding var hasChangedLocation: Bool

    func dropEntered(info: DropInfo) {
      guard item != draggedItem,
            let current = draggedItem,
            let from = data.firstIndex(of: current),
            let to = data.firstIndex(of: item)
      else {
        return
      }
      hasChangedLocation = true
      if data[to] != current {
        withAnimation {
          data.move(fromOffsets: IndexSet(integer: from),
                    toOffset: (to > from) ? to + 1 : to)
        }
      }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
      DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
      hasChangedLocation = false
      draggedItem = nil

      return true
    }
  }
}
