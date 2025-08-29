//
//  FavoriteFoodsViewModel.swift
//  Loop
//
//  Created by Noah Brauner on 7/27/23.
//  Copyright © 2023 LoopKit Authors. All rights reserved.
//

import SwiftUI
import HealthKit
import LoopKit
import Combine

final class FavoriteFoodsViewModel: ObservableObject {
    @Published var favoriteFoods = UserDefaults.standard.favoriteFoods
    @Published var selectedFood: StoredFavoriteFood?
    
    @Published var isDetailViewActive = false
    @Published var isEditViewActive = false
    @Published var isAddViewActive = false
    
    var preferredCarbUnit = HKUnit.gram()
    lazy var carbFormatter = QuantityFormatter(for: preferredCarbUnit)
    lazy var absorptionTimeFormatter: DateComponentsFormatter = {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.hour, .minute]
        formatter.unitsStyle = .abbreviated
        return formatter
    }()
    
    private lazy var cancellables = Set<AnyCancellable>()
    
    init() {
        observeFavoriteFoodChange()
    }
    
    func onFoodSave(_ newFood: NewFavoriteFood) {
        if isAddViewActive {
            let newStoredFood = StoredFavoriteFood(name: newFood.name, carbsQuantity: newFood.carbsQuantity, foodType: newFood.foodType, absorptionTime: newFood.absorptionTime)
            withAnimation {
                favoriteFoods.append(newStoredFood)
            }
            // Explicitly persist after add
            UserDefaults.standard.writeFavoriteFoods(favoriteFoods)
            isAddViewActive = false
            // Attempt to use any last AI image from carb entry context is not available here;
            // List view additions do not capture images, so we skip thumbnail here.
        }
        else if var selectedFood, let selectedFooxIndex = favoriteFoods.firstIndex(of: selectedFood) {
            selectedFood.name = newFood.name
            selectedFood.carbsQuantity = newFood.carbsQuantity
            selectedFood.foodType = newFood.foodType
            selectedFood.absorptionTime = newFood.absorptionTime
            favoriteFoods[selectedFooxIndex] = selectedFood
            // Explicitly persist after edit
            UserDefaults.standard.writeFavoriteFoods(favoriteFoods)
            isEditViewActive = false
        }
    }
    
    func onFoodDelete(_ food: StoredFavoriteFood) {
        if isDetailViewActive {
            isDetailViewActive = false
        }
        withAnimation {
            _ = favoriteFoods.remove(food)
        }
        // Explicitly persist after delete
        UserDefaults.standard.writeFavoriteFoods(favoriteFoods)
        // Remove thumbnail mapping and file if present
        var map = UserDefaults.standard.favoriteFoodImageIDs
        if let id = map[food.id] {
            FavoriteFoodImageStore.deleteThumbnail(id: id)
            map.removeValue(forKey: food.id)
            UserDefaults.standard.favoriteFoodImageIDs = map
        }
    }

    func onFoodReorder(from: IndexSet, to: Int) {
        withAnimation {
            favoriteFoods.move(fromOffsets: from, toOffset: to)
        }
        // Explicitly persist after reorder
        UserDefaults.standard.writeFavoriteFoods(favoriteFoods)
    }
    
    func addFoodTapped() {
        isAddViewActive = true
    }
    
    private func observeFavoriteFoodChange() {
        $favoriteFoods
            .dropFirst()
            .removeDuplicates()
            .sink { newValue in
                UserDefaults.standard.favoriteFoods = newValue
            }
            .store(in: &cancellables)
    }
}
