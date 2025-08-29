//
//  FavoriteFoodDetailView.swift
//  Loop
//
//  Created by Noah Brauner on 8/2/23.
//  Copyright © 2023 LoopKit Authors. All rights reserved.
//

import SwiftUI
import LoopKit
import HealthKit

public struct FavoriteFoodDetailView: View {
    let food: StoredFavoriteFood?
    let onFoodDelete: (StoredFavoriteFood) -> Void
    
    @State private var isConfirmingDelete = false
    
    let carbFormatter: QuantityFormatter
    let absorptionTimeFormatter: DateComponentsFormatter
    let preferredCarbUnit: HKUnit
    
    public init(food: StoredFavoriteFood?, onFoodDelete: @escaping (StoredFavoriteFood) -> Void, isConfirmingDelete: Bool = false, carbFormatter: QuantityFormatter, absorptionTimeFormatter: DateComponentsFormatter, preferredCarbUnit: HKUnit = HKUnit.gram()) {
        self.food = food
        self.onFoodDelete = onFoodDelete
        self.isConfirmingDelete = isConfirmingDelete
        self.carbFormatter = carbFormatter
        self.absorptionTimeFormatter = absorptionTimeFormatter
        self.preferredCarbUnit = preferredCarbUnit
    }
    
    public var body: some View {
        if let food {
            List {
                // Thumbnail (if available)
                if let thumb = thumbnailForFood(food) {
                    Section {
                        Image(uiImage: thumb)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(height: 160)
                            .frame(maxWidth: .infinity)
                            .clipped()
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                            .overlay(
                                RoundedRectangle(cornerRadius: 14)
                                    .stroke(Color(.separator), lineWidth: 0.5)
                            )
                    }
                    .listRowInsets(EdgeInsets(top: 12, leading: 12, bottom: 0, trailing: 12))
                }
                Section("Information") {
                    VStack(spacing: 16) {
                        let rows: [(field: String, value: String)] = [
                            ("Name", food.name),
                            ("Carb Quantity", food.carbsString(formatter: carbFormatter)),
                            ("Food Type", food.foodType),
                            ("Absorption Time", food.absorptionTimeString(formatter: absorptionTimeFormatter))
                        ]
                        ForEach(rows, id: \.field) { row in
                            HStack {
                                Text(row.field)
                                    .font(.subheadline)
                                Spacer()
                                Text(row.value)
                                    .font(.subheadline)
                            }
                        }
                    }
                }
                .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
                
                Button(role: .destructive, action: { isConfirmingDelete.toggle() }) {
                    Text("Delete Food")
                        .frame(maxWidth: .infinity, alignment: .center) // Align text in center
                }
            }
            .alert(isPresented: $isConfirmingDelete) {
                Alert(
                    title: Text("Delete “\(food.name)”?"),
                    message: Text("Are you sure you want to delete this food?"),
                    primaryButton: .cancel(),
                    secondaryButton: .destructive(Text("Delete"), action: { onFoodDelete(food) })
                )
            }
            .insetGroupedListStyle()
            .navigationTitle(food.title)
        }
    }
}

// MARK: - Thumbnail helper
extension FavoriteFoodDetailView {
    private func thumbnailForFood(_ food: StoredFavoriteFood) -> UIImage? {
        let map = UserDefaults.standard.favoriteFoodImageIDs
        guard let id = map[food.id] else { return nil }
        return FavoriteFoodImageStore.loadThumbnail(id: id)
    }
}
