//
//  CarbEntryView.swift
//  Loop
//
//  Created by Noah Brauner on 7/19/23.
//  Copyright © 2023 LoopKit Authors. All rights reserved.
//

import SwiftUI
import LoopKit
import LoopKitUI
import HealthKit
import UIKit
import os.log

struct CarbEntryView: View, HorizontalSizeClassOverride {
    @EnvironmentObject private var displayGlucosePreference: DisplayGlucosePreference
    @Environment(\.dismissAction) private var dismiss

    @ObservedObject var viewModel: CarbEntryViewModel
        
    @State private var expandedRow: Row?
    
    @State private var showHowAbsorptionTimeWorks = false
    @State private var showAddFavoriteFood = false
    @State private var showingAICamera = false
    @State private var showingAISettings = false
    
    private let isNewEntry: Bool

    init(viewModel: CarbEntryViewModel) {
        if viewModel.shouldBeginEditingQuantity {
            expandedRow = .amountConsumed
        }
        isNewEntry = viewModel.originalCarbEntry == nil
        self.viewModel = viewModel
    }
    
    var body: some View {
        if isNewEntry {
            NavigationView {
                let title = NSLocalizedString("carb-entry-title-add", value: "Add Carb Entry", comment: "The title of the view controller to create a new carb entry")
                content
                    .navigationBarTitle(title, displayMode: .inline)
                    .toolbar {
                        ToolbarItem(placement: .navigationBarLeading) {
                            dismissButton
                        }
                        
                        ToolbarItem(placement: .navigationBarTrailing) {
                            continueButton
                        }
                    }
                
            }
            .navigationViewStyle(StackNavigationViewStyle())
        } else {
            content
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        continueButton
                    }
                }
        }
    }
    
    private var content: some View {
        ZStack {
            Color(.systemGroupedBackground)
                .edgesIgnoringSafeArea(.all)
                .onTapGesture {
                    // Dismiss keyboard when tapping background
                    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                }
            
            ScrollView {
                warningsCard

                mainCard
                    .padding(.top, 8)
                
                continueActionButton
                
                if isNewEntry, FeatureFlags.allowExperimentalFeatures {
                    favoriteFoodsCard
                }
                
                let isBolusViewActive = Binding(get: { viewModel.bolusViewModel != nil }, set: { _, _ in viewModel.bolusViewModel = nil })
                NavigationLink(destination: bolusView, isActive: isBolusViewActive) {
                    EmptyView()
                }
                .frame(width: 0, height: 0)
                .opacity(0)
                .accessibility(hidden: true)
            }
        }
        .alert(item: $viewModel.alert, content: alert(for:))
        .sheet(isPresented: $showAddFavoriteFood, onDismiss: clearExpandedRow) {
            AddEditFavoriteFoodView(carbsQuantity: viewModel.carbsQuantity, foodType: viewModel.foodType, absorptionTime: viewModel.absorptionTime, onSave: onFavoriteFoodSave(_:))
        }
        .sheet(isPresented: $showHowAbsorptionTimeWorks) {
            HowAbsorptionTimeWorksView()
        }
        .sheet(isPresented: $showingAICamera) {
            AICameraView(
                onFoodAnalyzed: { result, capturedImage in
                    Task { @MainActor in
                        handleAIFoodAnalysis(result)
                        viewModel.capturedAIImage = capturedImage
                        showingAICamera = false
                    }
                },
                onCancel: {
                    showingAICamera = false
                }
            )
        }
        .sheet(isPresented: $showingAISettings) {
            AISettingsView()
        }
    }
    
    private var mainCard: some View {
        VStack(spacing: 10) {
            let amountConsumedFocused: Binding<Bool> = Binding(get: { expandedRow == .amountConsumed }, set: { expandedRow = $0 ? .amountConsumed : nil })
            let timeFocused: Binding<Bool> = Binding(get: { expandedRow == .time }, set: { expandedRow = $0 ? .time : nil })
            let foodTypeFocused: Binding<Bool> = Binding(get: { expandedRow == .foodType }, set: { expandedRow = $0 ? .foodType : nil })
            let absorptionTimeFocused: Binding<Bool> = Binding(get: { expandedRow == .absorptionTime }, set: { expandedRow = $0 ? .absorptionTime : nil })
            
            CarbQuantityRow(quantity: $viewModel.carbsQuantity, isFocused: amountConsumedFocused, title: NSLocalizedString("Amount Consumed", comment: "Label for carb quantity entry row on carb entry screen"), preferredCarbUnit: viewModel.preferredCarbUnit)
            
            // Food search section - moved up from bottom
            if isNewEntry && UserDefaults.standard.foodSearchEnabled {
                CardSectionDivider()
                
                VStack(spacing: 16) {
                    // Section header
                    HStack {
                        Text("Search for Food")
                            .font(.headline)
                            .foregroundColor(.primary)
                        
                        Spacer()
                        
                        // AI Settings button
                        Button(action: {
                            showingAISettings = true
                        }) {
                            Image(systemName: "gear")
                                .foregroundColor(.secondary)
                                .font(.system(size: 24))
                        }
                        .accessibilityLabel("AI Settings")
                    }
                    
                    // Search bar with barcode and AI camera buttons
                    FoodSearchBar(
                        searchText: $viewModel.foodSearchText,
                        onBarcodeScanTapped: {
                            // Barcode scanning is handled by FoodSearchBar's sheet presentation
                        },
                        onAICameraTapped: {
                            // Handle AI camera
                            showingAICamera = true
                        }
                    )
                    
                    // Quick search suggestions (shown when no search text and no results)
                    if viewModel.foodSearchText.isEmpty && viewModel.foodSearchResults.isEmpty && !viewModel.isFoodSearching {
                        QuickSearchSuggestions { suggestion in
                            // Handle suggestion tap
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            viewModel.foodSearchText = suggestion
                            viewModel.performFoodSearch(query: suggestion)
                        }
                        .transition(.opacity.combined(with: .scale(scale: 0.95)))
                    }
                    
                    // Search results
                    if viewModel.isFoodSearching || viewModel.showingFoodSearch || !viewModel.foodSearchResults.isEmpty {
                        FoodSearchResultsView(
                            searchResults: viewModel.foodSearchResults,
                            isSearching: viewModel.isFoodSearching,
                            errorMessage: viewModel.foodSearchError,
                            onProductSelected: { product in
                                viewModel.selectFoodProduct(product)
                            }
                        )
                        .onAppear {
                        }
                    }
                }
                .onAppear {
                    // Setup food search observers when the view appears
                    viewModel.setupFoodSearchObservers()
                }
                
                CardSectionDivider()
            }
            
            // Food-related rows (only show if food search is enabled)
            if UserDefaults.standard.foodSearchEnabled {
                // Always show servings row when food search is enabled
                ServingsDisplayRow(
                servings: $viewModel.numberOfServings, 
                servingSize: viewModel.selectedFoodServingSize,
                selectedFoodProduct: viewModel.selectedFoodProduct
            )
            .id("servings-\(viewModel.selectedFoodProduct?.id ?? "none")")
            .onAppear {
            }
            .onChange(of: viewModel.numberOfServings) { newServings in
                // Force recalculation if we have a selected food product
                if let selectedFood = viewModel.selectedFoodProduct {
                    let expectedCarbs = (selectedFood.carbsPerServing ?? selectedFood.nutriments.carbohydrates) * newServings
                    
                    // Force update the carbs quantity if it doesn't match
                    if abs((viewModel.carbsQuantity ?? 0) - expectedCarbs) > 0.01 {
                        viewModel.carbsQuantity = expectedCarbs
                    }
                }
            }
            
            // Clean product information for scanned items
            if let selectedFood = viewModel.selectedFoodProduct {
                VStack(spacing: 12) {
                    // Product image at the top (works for both barcode and AI scanned images)
                    if let capturedImage = viewModel.capturedAIImage {
                        // Show AI captured image
                        Image(uiImage: capturedImage)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 120, height: 90)
                            .clipped()
                            .cornerRadius(12)
                    } else if let imageURL = selectedFood.imageFrontUrl ?? selectedFood.imageURL, !imageURL.isEmpty {
                        // Show barcode product image from URL
                        AsyncImage(url: URL(string: imageURL)) { image in
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(width: 120, height: 90)
                                .clipped()
                                .cornerRadius(12)
                        } placeholder: {
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color(.systemGray6))
                                .frame(width: 120, height: 90)
                                .overlay(
                                    VStack(spacing: 4) {
                                        ProgressView()
                                            .scaleEffect(0.8)
                                        Text("Loading...")
                                            .font(.caption2)
                                            .foregroundColor(.secondary)
                                    }
                                )
                        }
                    }
                    
                    // Product name
                    Text(selectedFood.displayName)
                        .font(.headline)
                        .fontWeight(.medium)
                        .foregroundColor(.primary)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                    
                    // Package serving size (only show "Package Serving Size:" prefix for barcode scans)
                    Text(selectedFood.dataSource == .barcodeScan ? "Package Serving Size: \(selectedFood.servingSizeDisplay)" : selectedFood.servingSizeDisplay)
                        .font(.subheadline)
                        .foregroundColor(.primary)
                }
                .padding(.vertical, 16)
                .padding(.horizontal, 16)
                .background(Color(.systemGray6))
                .cornerRadius(12)
                .padding(.horizontal)
                .padding(.top, 8)
                
                // Animated nutrition circles right below the product info
                VStack(spacing: 8) {
                    // Circular nutrition indicators
                    HStack(spacing: 8) {
                        // Carbohydrates (first)
                        NutritionCircle(
                            value: (selectedFood.carbsPerServing ?? selectedFood.nutriments.carbohydrates) * viewModel.numberOfServings,
                            unit: "g",
                            label: "Carbs",
                            color: Color(red: 0.4, green: 0.7, blue: 1.0), // Light blue
                            maxValue: 50.0 // Typical daily carb portion
                        )
                        
                        // Calories (second)
                        if let calories = selectedFood.caloriesPerServing {
                            NutritionCircle(
                                value: calories * viewModel.numberOfServings,
                                unit: "cal",
                                label: "Calories",
                                color: Color(red: 0.5, green: 0.8, blue: 0.4), // Green
                                maxValue: 500.0 // Typical meal calories
                            )
                        }
                        
                        // Fat (third)
                        if let fat = selectedFood.fatPerServing {
                            NutritionCircle(
                                value: fat * viewModel.numberOfServings,
                                unit: "g",
                                label: "Fat", 
                                color: Color(red: 1.0, green: 0.8, blue: 0.2), // Golden yellow
                                maxValue: 20.0 // Typical fat portion
                            )
                        }
                        
                        // Protein (fourth)
                        if let protein = selectedFood.proteinPerServing {
                            NutritionCircle(
                                value: protein * viewModel.numberOfServings,
                                unit: "g", 
                                label: "Protein",
                                color: Color(red: 1.0, green: 0.4, blue: 0.4), // Coral/red
                                maxValue: 30.0 // Typical protein portion
                            )
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .id("nutrition-circles-\(viewModel.numberOfServings)")
                }
                .padding(.vertical, 12)
                .padding(.horizontal, 16)
                .background(Color(.systemGray6))
                .cornerRadius(12)
                .padding(.horizontal)
                .padding(.top, 8)
            }
            
            
            // Concise AI Analysis Notes (moved below nutrition circles)
            if let aiResult = viewModel.lastAIAnalysisResult {
                VStack(spacing: 8) {
                    // Detailed Food Breakdown (expandable)
                    if !aiResult.foodItemsDetailed.isEmpty {
                        detailedFoodBreakdownSection(aiResult: aiResult)
                    }
                    
                    // Portion estimation method (expandable)
                    if let portionMethod = aiResult.portionAssessmentMethod, !portionMethod.isEmpty {
                        ExpandableNoteView(
                            icon: "ruler",
                            iconColor: .blue,
                            title: "Portions & Servings:",
                            content: portionMethod,
                            backgroundColor: Color(.systemBlue).opacity(0.08)
                        )
                    }
                    
                    // Diabetes considerations (expandable)
                    if let diabetesNotes = aiResult.diabetesConsiderations, !diabetesNotes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        ExpandableNoteView(
                            icon: "heart.fill",
                            iconColor: .red,
                            title: "Diabetes Note:",
                            content: diabetesNotes,
                            backgroundColor: Color(.systemRed).opacity(0.08)
                        )
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
            }
            } // End food search enabled section

            CardSectionDivider()
            
            DatePickerRow(date: $viewModel.time, isFocused: timeFocused, minimumDate: viewModel.minimumDate, maximumDate: viewModel.maximumDate)
            
            CardSectionDivider()
            
            FoodTypeRow(foodType: $viewModel.foodType, absorptionTime: $viewModel.absorptionTime, selectedDefaultAbsorptionTimeEmoji: $viewModel.selectedDefaultAbsorptionTimeEmoji, usesCustomFoodType: $viewModel.usesCustomFoodType, absorptionTimeWasEdited: $viewModel.absorptionTimeWasEdited, isFocused: foodTypeFocused, defaultAbsorptionTimes: viewModel.defaultAbsorptionTimes)
            
            CardSectionDivider()
            
            AbsorptionTimePickerRow(absorptionTime: $viewModel.absorptionTime, isFocused: absorptionTimeFocused, validDurationRange: viewModel.absorptionRimesRange, showHowAbsorptionTimeWorks: $showHowAbsorptionTimeWorks)
                .padding(.bottom, 2)
        }
        .padding(.vertical, 12)
        .padding(.horizontal)
        .background(CardBackground())
        .padding(.horizontal)
    }
    
    @ViewBuilder
    private var bolusView: some View {
        if let viewModel = viewModel.bolusViewModel {
            BolusEntryView(viewModel: viewModel)
                .environmentObject(displayGlucosePreference)
                .environment(\.dismissAction, dismiss)
        }
    }
    
    private func clearExpandedRow() {
        self.expandedRow = nil
    }
    
    /// Handle AI food analysis results by converting to food product format
    @MainActor
    private func handleAIFoodAnalysis(_ result: AIFoodAnalysisResult) {
        // Store the detailed AI result for UI display
        viewModel.lastAIAnalysisResult = result
        
        // Convert AI result to OpenFoodFactsProduct format for consistency
        let aiProduct = convertAIResultToFoodProduct(result)
        
        // Use existing food selection workflow
        viewModel.selectFoodProduct(aiProduct)
        
        // Set the number of servings from AI analysis AFTER selecting the product
        viewModel.numberOfServings = result.servings
        
    }
    
    /// Convert AI analysis result to OpenFoodFactsProduct for integration with existing workflow
    private func convertAIResultToFoodProduct(_ result: AIFoodAnalysisResult) -> OpenFoodFactsProduct {
        // Create synthetic ID for AI-generated products
        let aiId = "ai_\(UUID().uuidString.prefix(8))"
        
        // Extract actual food name for the main display, not the portion description
        let displayName = extractFoodNameFromAIResult(result)
        
        // Calculate per-serving nutrition values for proper scaling
        let servingsAmount = max(1.0, result.servings) // Ensure at least 1 serving to avoid division by zero
        let carbsPerServing = result.carbohydrates / servingsAmount
        let proteinPerServing = (result.protein ?? 0) / servingsAmount
        let fatPerServing = (result.fat ?? 0) / servingsAmount
        let caloriesPerServing = (result.calories ?? 0) / servingsAmount
        
        // Create nutriments with per-serving values so they scale correctly
        let nutriments = Nutriments(
            carbohydrates: carbsPerServing,
            proteins: proteinPerServing > 0 ? proteinPerServing : nil,
            fat: fatPerServing > 0 ? fatPerServing : nil,
            calories: caloriesPerServing > 0 ? caloriesPerServing : nil
        )
        
        // Use serving size description for the "Based on" text
        let servingSizeDisplay = result.servingSizeDescription
        
        // Include analysis notes in categories field for display
        let analysisInfo = result.analysisNotes ?? "AI food recognition analysis"
        
        return OpenFoodFactsProduct(
            id: aiId,
            productName: displayName.isEmpty ? "AI Analyzed Food" : displayName,
            brands: "AI Analysis",
            categories: analysisInfo,
            nutriments: nutriments,
            servingSize: servingSizeDisplay,
            servingQuantity: 100.0, // Use as base for per-serving calculations
            imageURL: nil,
            imageFrontUrl: nil,
            code: nil
        )
    }
    
    /// Extract clean food name from AI analysis result for Food Type field
    private func extractFoodNameFromAIResult(_ result: AIFoodAnalysisResult) -> String {
        // Try to get the actual food name from the detailed analysis
        if let firstName = result.foodItemsDetailed.first?.name, !firstName.isEmpty {
            return cleanFoodNameForDisplay(firstName)
        }
        
        // Fallback to first food item from basic list
        if let firstFood = result.foodItems.first, !firstFood.isEmpty {
            return cleanFoodNameForDisplay(firstFood)
        }
        
        // If we have an overallDescription, try to extract a clean food name from it
        if let overallDesc = result.overallDescription, !overallDesc.isEmpty {
            return cleanFoodNameForDisplay(overallDesc)
        }
        
        // Last resort fallback
        return "AI Analyzed Food"
    }
    
    /// Clean up food name for display in Food Type field
    private func cleanFoodNameForDisplay(_ name: String) -> String {
        var cleaned = name
        
        // Remove measurement words and qualifiers that shouldn't be in food names
        let wordsToRemove = [
            "Approximately", "About", "Around", "Roughly", "Nearly",
            "ounces", "ounce", "oz", "grams", "gram", "g", "pounds", "pound", "lbs", "lb",
            "cups", "cup", "tablespoons", "tablespoon", "tbsp", "teaspoons", "teaspoon", "tsp",
            "slices", "slice", "pieces", "piece", "servings", "serving", "portions", "portion"
        ]
        
        // Remove these words with case-insensitive matching
        for word in wordsToRemove {
            let pattern = "\\b\(word)\\b"
            cleaned = cleaned.replacingOccurrences(of: pattern, with: "", options: [.regularExpression, .caseInsensitive])
        }
        
        // Remove numbers at the beginning (like "4 ounces of chicken" -> "chicken")
        cleaned = cleaned.replacingOccurrences(of: "^\\d+(\\.\\d+)?\\s*", with: "", options: .regularExpression)
        
        // Use centralized prefix cleaning from AIFoodAnalysis
        cleaned = ConfigurableAIService.cleanFoodText(cleaned) ?? cleaned
        
        // Clean up extra whitespace
        cleaned = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
        cleaned = cleaned.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        
        return cleaned.isEmpty ? "Mixed Food" : cleaned
    }
    
    /// Remove redundant "food" words and clean up descriptions
    private func cleanFoodDescription(_ description: String) -> String {
        let cleaned = description
            .replacingOccurrences(of: "Food, ", with: "")  // Remove "Food, " from beginning
            .replacingOccurrences(of: "food, ", with: "")  // Remove "food, " from beginning
            .replacingOccurrences(of: " Food", with: "")   // Remove " Food" from anywhere
            .replacingOccurrences(of: "Food ", with: "")   // Remove "Food " from anywhere
            .replacingOccurrences(of: "food", with: "")    // Remove "food" from anywhere
            .replacingOccurrences(of: "Unknown", with: "Mixed Items")
            .trimmingCharacters(in: .whitespaces)
        
        return cleaned.isEmpty ? "Mixed Items" : cleaned
    }
}

// MARK: - Warnings & Alerts
extension CarbEntryView {
    private var warningsCard: some View {
        ForEach(Array(viewModel.warnings).sorted(by: { $0.priority < $1.priority })) { warning in
            warningView(for: warning)
                .padding(.vertical, 8)
                .padding(.horizontal)
                .background(CardBackground())
                .padding(.horizontal)
                .padding(.top, 8)
        }
    }
    
    private func warningView(for warning: CarbEntryViewModel.Warning) -> some View {
        HStack {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(triangleColor(for: warning))
            
            Text(warningText(for: warning))
                .font(.caption)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    
    private func triangleColor(for warning: CarbEntryViewModel.Warning) -> Color {
        switch warning {
        case .entryIsMissedMeal:
            return .critical
        case .overrideInProgress:
            return .warning
        }
    }
    
    private func warningText(for warning: CarbEntryViewModel.Warning) -> String {
        switch warning {
        case .entryIsMissedMeal:
            return NSLocalizedString("Loop has detected an missed meal and estimated its size. Edit the carb amount to match the amount of any carbs you may have eaten.", comment: "Warning displayed when user is adding a meal from an missed meal notification")
        case .overrideInProgress:
            return NSLocalizedString("An active override is modifying your carb ratio and insulin sensitivity. If you don't want this to affect your bolus calculation and projected glucose, consider turning off the override.", comment: "Warning to ensure the carb entry is accurate during an override")
        }
    }
    
    private func alert(for alert: CarbEntryViewModel.Alert) -> SwiftUI.Alert {
        switch alert {
        case .maxQuantityExceded:
            let message = String(
                format: NSLocalizedString("The maximum allowed amount is %@ grams.", comment: "Alert body displayed for quantity greater than max (1: maximum quantity in grams)"),
                NumberFormatter.localizedString(from: NSNumber(value: viewModel.maxCarbEntryQuantity.doubleValue(for: viewModel.preferredCarbUnit)), number: .none)
            )
            let okMessage = NSLocalizedString("com.loudnate.LoopKit.errorAlertActionTitle", value: "OK", comment: "The title of the action used to dismiss an error alert")
            return SwiftUI.Alert(
                title: Text("Large Meal Entered", comment: "Title of the warning shown when a large meal was entered"),
                message: Text(message),
                dismissButton: .cancel(Text(okMessage), action: viewModel.clearAlert)
            )
        case .warningQuantityValidation:
            let message = String(
                format: NSLocalizedString("Did you intend to enter %1$@ grams as the amount of carbohydrates for this meal?", comment: "Alert body when entered carbohydrates is greater than threshold (1: entered quantity in grams)"),
                NumberFormatter.localizedString(from: NSNumber(value: viewModel.carbsQuantity ?? 0), number: .none)
            )
            return SwiftUI.Alert(
                title: Text("Large Meal Entered", comment: "Title of the warning shown when a large meal was entered"),
                message: Text(message),
                primaryButton: .default(Text("No, edit amount", comment: "The title of the action used when rejecting the the amount of carbohydrates entered."), action: viewModel.clearAlert),
                secondaryButton: .cancel(Text("Yes", comment: "The title of the action used when confirming entered amount of carbohydrates."), action: viewModel.clearAlertAndContinueToBolus)
            )
        }
    }
}

// MARK: - Favorite Foods Card
extension CarbEntryView {
    private var favoriteFoodsCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("FAVORITE FOODS")
                .font(.footnote)
                .foregroundColor(.secondary)
                .padding(.horizontal, 26)
            
            VStack(spacing: 10) {
                if !viewModel.favoriteFoods.isEmpty {
                    VStack {
                        HStack {
                            Text("Choose Favorite:")
                            
                            let selectedFavorite = favoritedFoodTextFromIndex(viewModel.selectedFavoriteFoodIndex)
                            Text(selectedFavorite)
                                .minimumScaleFactor(0.8)
                                .frame(maxWidth: .infinity, alignment: .trailing)
                        }
                        
                        if expandedRow == .favoriteFoodSelection {
                            Picker("", selection: $viewModel.selectedFavoriteFoodIndex) {
                                ForEach(-1..<viewModel.favoriteFoods.count, id: \.self) { index in
                                    Text(favoritedFoodTextFromIndex(index))
                                        .tag(index)
                                }
                            }
                            .pickerStyle(.wheel)
                        }
                    }
                    .onTapGesture {
                        withAnimation {
                            if expandedRow == .favoriteFoodSelection {
                                expandedRow = nil
                            } else {
                                expandedRow = .favoriteFoodSelection
                            }
                        }
                    }
                    
                    CardSectionDivider()
                }
                
                Button(action: saveAsFavoriteFood) {
                    Text("Save as favorite food")
                        .frame(maxWidth: .infinity)
                }
                .disabled(viewModel.saveFavoriteFoodButtonDisabled)
            }
            .padding(.vertical, 12)
            .padding(.horizontal)
            .background(CardBackground())
            .padding(.horizontal)
        }
    }
    
    private func favoritedFoodTextFromIndex(_ index: Int) -> String {
        if index == -1 {
            return "None"
        } else {
            let food = viewModel.favoriteFoods[index]
            return "\(food.name) \(food.foodType)"
        }
    }
    
    private func saveAsFavoriteFood() {
        self.showAddFavoriteFood = true
    }
    
    private func onFavoriteFoodSave(_ food: NewFavoriteFood) {
        clearExpandedRow()
        self.showAddFavoriteFood = false
        viewModel.onFavoriteFoodSave(food)
    }
}

// MARK: - Other UI Elements
extension CarbEntryView {
    private var dismissButton: some View {
        Button(action: dismiss) {
            Text("Cancel")
        }
    }
    
    private var continueButton: some View {
        Button(action: viewModel.continueToBolus) {
            Text("Continue")
        }
        .disabled(viewModel.continueButtonDisabled)
    }
    
    private var continueActionButton: some View {
        Button(action: viewModel.continueToBolus) {
            Text("Continue")
        }
        .buttonStyle(ActionButtonStyle())
        .padding()
        .disabled(viewModel.continueButtonDisabled)
    }
    
    @ViewBuilder
    private func detailedFoodBreakdownSection(aiResult: AIFoodAnalysisResult) -> some View {
        VStack(spacing: 0) {
            // Expandable header
            HStack {
                Image(systemName: "list.bullet.rectangle.fill")
                    .foregroundColor(.orange)
                    .font(.system(size: 16, weight: .medium))
                
                Text("Food Details")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Spacer()
                
                Text("(\(aiResult.foodItemsDetailed.count) items)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Image(systemName: expandedRow == .detailedFoodBreakdown ? "chevron.up" : "chevron.down")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color(.systemOrange).opacity(0.08))
            .cornerRadius(12)
            .onTapGesture {
                withAnimation(.easeInOut(duration: 0.3)) {
                    expandedRow = expandedRow == .detailedFoodBreakdown ? nil : .detailedFoodBreakdown
                }
            }
            
            // Expandable content
            if expandedRow == .detailedFoodBreakdown {
                VStack(spacing: 12) {
                    ForEach(Array(aiResult.foodItemsDetailed.enumerated()), id: \.offset) { index, foodItem in
                        FoodItemDetailRow(foodItem: foodItem, itemNumber: index + 1)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(Color(.systemBackground))
                .cornerRadius(12)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color(.systemOrange).opacity(0.3), lineWidth: 1)
                )
                .padding(.top, 4)
            }
        }
    }
    
}

extension CarbEntryView {
    enum Row {
        case amountConsumed, time, foodType, absorptionTime, favoriteFoodSelection, detailedFoodBreakdown
    }
}

// MARK: - ServingsRow Component

/// A row that always displays servings information
struct ServingsDisplayRow: View {
    @Binding var servings: Double
    let servingSize: String?
    let selectedFoodProduct: OpenFoodFactsProduct?
    
    private let formatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 1
        formatter.minimumFractionDigits = 0
        return formatter
    }()
    
    var body: some View {
        let hasSelectedFood = selectedFoodProduct != nil
        
        return HStack {
            Text("Servings")
                .foregroundColor(.primary)
            
            Spacer()
            
            if hasSelectedFood {
                // Debug: Print current state
                // Show stepper controls when food is selected
                HStack(spacing: 8) {
                    // Decrease button
                    Button(action: {
                        let newValue = max(0.5, servings - 0.5)
                        servings = newValue
                    }) {
                        Image(systemName: "minus.circle.fill")
                            .font(.title3)
                            .foregroundColor(servings > 0.5 ? .accentColor : .secondary)
                    }
                    .disabled(servings <= 0.5)
                    
                    // Current value
                    Text(formatter.string(from: NSNumber(value: servings)) ?? "1")
                        .font(.body)
                        .foregroundColor(.primary)
                        .frame(minWidth: 30)
                    
                    // Increase button
                    Button(action: {
                        let newValue = min(10.0, servings + 0.5)
                        servings = newValue
                    }) {
                        Image(systemName: "plus.circle.fill")
                            .font(.title3)
                            .foregroundColor(servings < 10.0 ? .accentColor : .secondary)
                    }
                    .disabled(servings >= 10.0)
                }
            } else {
                // Show placeholder when no food is selected
                Text("—")
                    .font(.body)
                    .foregroundColor(.secondary)
            }
        }
        .frame(height: 44)
        .padding(.vertical, -8)
    }
}

/// A row for adjusting the number of servings with stepper controls
struct ServingsRow: View {
    @Binding var servings: Double
    let servingSize: String
    
    private let formatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 1
        formatter.minimumFractionDigits = 0
        return formatter
    }()
    
    var body: some View {
        VStack(spacing: 6) {
            HStack {
                Text("Servings")
                    .foregroundColor(.primary)
                
                Spacer()
                
                // Stepper with custom appearance
                HStack(spacing: 8) {
                    // Decrease button
                    Button(action: {
                        let newValue = max(0.5, servings - 0.5)
                        servings = newValue
                    }) {
                        Image(systemName: "minus.circle.fill")
                            .font(.title3)
                            .foregroundColor(servings > 0.5 ? .accentColor : .secondary)
                    }
                    .disabled(servings <= 0.5)
                    
                    // Current value
                    Text(formatter.string(from: NSNumber(value: servings)) ?? "1")
                        .font(.body)
                        .foregroundColor(.primary)
                        .frame(minWidth: 30)
                    
                    // Increase button
                    Button(action: {
                        let newValue = min(10.0, servings + 0.5)
                        servings = newValue
                    }) {
                        Image(systemName: "plus.circle.fill")
                            .font(.title3)
                            .foregroundColor(servings < 10.0 ? .accentColor : .secondary)
                    }
                    .disabled(servings >= 10.0)
                }
            }
            
            // Serving size description
            HStack {
                Text("(\(servingSize) each)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
            }
        }
        .frame(minHeight: 44)
    }
}

// MARK: - Nutrition Circle Component

/// Circular progress indicator for nutrition values with enhanced animations
struct NutritionCircle: View {
    let value: Double
    let unit: String
    let label: String
    let color: Color
    let maxValue: Double
    
    @State private var animatedValue: Double = 0
    @State private var animatedProgress: Double = 0
    @State private var isLoading: Bool = false
    
    private var progress: Double {
        min(value / maxValue, 1.0)
    }
    
    private var displayValue: String {
        // Format animated value to 1 decimal place, but hide .0 for whole numbers
        if animatedValue.truncatingRemainder(dividingBy: 1) == 0 {
            return String(format: "%.0f", animatedValue)
        } else {
            return String(format: "%.1f", animatedValue)
        }
    }
    
    var body: some View {
        VStack(spacing: 4) {
            ZStack {
                // Background circle
                Circle()
                    .stroke(Color.gray.opacity(0.3), lineWidth: 4)
                    .frame(width: 70, height: 70)
                
                if isLoading {
                    // Loading spinner
                    ProgressView()
                        .scaleEffect(0.8)
                        .foregroundColor(color)
                } else {
                    // Progress circle with smooth animation
                    Circle()
                        .trim(from: 0.0, to: animatedProgress)
                        .stroke(color, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                        .frame(width: 70, height: 70)
                        .rotationEffect(.degrees(-90))
                        .animation(.spring(response: 0.8, dampingFraction: 0.8), value: animatedProgress)
                    
                    // Center text with count-up animation
                    HStack(spacing: 1) {
                        Text(displayValue)
                            .font(.system(size: 16.5, weight: .bold))
                            .foregroundColor(.primary)
                            .animation(.easeInOut(duration: 0.2), value: animatedValue)
                        Text(unit)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.secondary)
                            .offset(y: 1)
                    }
                }
            }
            .onAppear {
                // Start count-up animation when circle appears
                withAnimation(.easeOut(duration: 1.0)) {
                    animatedValue = value
                    animatedProgress = progress
                }
            }
            .onChange(of: value) { newValue in
                // Smooth value transitions when data changes
                if newValue == 0 {
                    // Show loading state for empty values
                    isLoading = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        isLoading = false
                        withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {
                            animatedValue = newValue
                            animatedProgress = min(newValue / maxValue, 1.0)
                        }
                    }
                } else {
                    // Immediate transition for real values
                    withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {
                        animatedValue = newValue
                        animatedProgress = min(newValue / maxValue, 1.0)
                    }
                }
            }
            
            // Label
            Text(label)
                .font(.caption2)
                .foregroundColor(.primary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Expandable Note Component

/// Expandable view for AI analysis notes that can be tapped to show full content
struct ExpandableNoteView: View {
    let icon: String
    let iconColor: Color
    let title: String
    let content: String
    let backgroundColor: Color
    
    @State private var isExpanded = false
    
    private var truncatedContent: String {
        content.components(separatedBy: ".").first ?? content
    }
    
    private var hasMoreContent: Bool {
        content.count > truncatedContent.count
    }
    
    private var borderColor: Color {
        // Extract border color from background color
        if backgroundColor == Color(.systemBlue).opacity(0.08) {
            return Color(.systemBlue).opacity(0.3)
        } else if backgroundColor == Color(.systemRed).opacity(0.08) {
            return Color(.systemRed).opacity(0.3)
        } else {
            return Color(.systemGray4)
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Expandable header (always visible) - matches Food Details style
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.caption)
                    .foregroundColor(iconColor)
                
                Text(title)
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(.secondary)
                
                Spacer()
                
                // Show truncated content when collapsed, or nothing when expanded
                if !isExpanded {
                    Text(truncatedContent)
                        .font(.caption2)
                        .foregroundColor(.primary)
                        .lineLimit(1)
                }
                
                // Expansion indicator
                if hasMoreContent {
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .animation(.easeInOut(duration: 0.3), value: isExpanded)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(backgroundColor)
            .cornerRadius(12)
            .contentShape(Rectangle()) // Makes entire area tappable
            .onTapGesture {
                if hasMoreContent {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        isExpanded.toggle()
                    }
                }
            }
            
            // Expandable content (matches Food Details style)
            if isExpanded {
                VStack(alignment: .leading, spacing: 8) {
                    Text(content)
                        .font(.caption2)
                        .foregroundColor(.primary)
                        .lineLimit(nil)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(Color(.systemBackground))
                .cornerRadius(12)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(borderColor, lineWidth: 1)
                )
                .padding(.top, 4)
            }
        }
    }
}

// MARK: - Quick Search Suggestions Component

/// Quick search suggestions for common foods
struct QuickSearchSuggestions: View {
    let onSuggestionTapped: (String) -> Void
    
    private let suggestions = [
        ("🍎", "Apple"), ("🍌", "Banana"), ("🍞", "Bread"),
        ("🍚", "Rice"), ("🍗", "Chicken"), ("🍝", "Pasta"),
        ("🥛", "Milk"), ("🧀", "Cheese"), ("🥚", "Eggs"),
        ("🥔", "Potato"), ("🥕", "Carrot"), ("🍅", "Tomato")
    ]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Popular Foods")
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.horizontal)
            
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 8) {
                    ForEach(suggestions, id: \.1) { emoji, name in
                        Button(action: {
                            onSuggestionTapped(name)
                        }) {
                            HStack(spacing: 6) {
                                Text(emoji)
                                    .font(.system(size: 16))
                                Text(name)
                                    .font(.caption)
                                    .fontWeight(.medium)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(Color(.systemGray6))
                            .foregroundColor(.primary)
                            .cornerRadius(16)
                            .overlay(
                                RoundedRectangle(cornerRadius: 16)
                                    .stroke(Color(.systemGray4), lineWidth: 0.5)
                            )
                        }
                        .buttonStyle(PlainButtonStyle())
                        .scaleEffect(1.0)
                        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: false)
                    }
                }
                .padding(.horizontal)
            }
        }
        .padding(.bottom, 8)
    }
}

// MARK: - Product Image Component

/// Product image view for displaying scanned product photos
struct ProductImageView: View {
    let imageURL: String
    let productName: String
    
    @State private var isLoading = true
    @State private var loadError = false
    
    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                // Background placeholder
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(.systemGray6))
                    .frame(width: 120, height: 90)
                
                if loadError {
                    // Error state
                    VStack(spacing: 4) {
                        Image(systemName: "photo")
                            .font(.system(size: 24))
                            .foregroundColor(.secondary)
                        Text("No Image")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                } else {
                    // Async image loading
                    AsyncImage(url: URL(string: imageURL)) { image in
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 120, height: 90)
                            .clipped()
                            .cornerRadius(12)
                            .onAppear {
                                isLoading = false
                            }
                    } placeholder: {
                        if isLoading {
                            VStack(spacing: 4) {
                                ProgressView()
                                    .scaleEffect(0.8)
                                Text("Loading...")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    .onAppear {
                        // Reset states when URL changes
                        isLoading = true
                        loadError = false
                    }
                    .onChange(of: imageURL) { _ in
                        isLoading = true
                        loadError = false
                    }
                }
            }
            
            // Product name caption
            Text(productName)
                .font(.caption)
                .foregroundColor(.primary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .frame(maxWidth: 120)
        }
        .onAppear {
            // Simulate network delay for error handling
            DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) {
                if isLoading {
                    loadError = true
                    isLoading = false
                }
            }
        }
    }
}

// MARK: - Food Item Detail Row Component

/// Individual food item detail row for the breakdown section
struct FoodItemDetailRow: View {
    let foodItem: FoodItemAnalysis
    let itemNumber: Int
    
    var body: some View {
        VStack(spacing: 8) {
            // Header with food name and carbs
            HStack {
                // Item number
                Text("\(itemNumber).")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(width: 20, alignment: .leading)
                
                // Food name
                Text(foodItem.name)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.primary)
                    .lineLimit(2)
                
                Spacer()
                
                // Carbs amount (highlighted)
                HStack(spacing: 4) {
                    Text("\(String(format: "%.1f", foodItem.carbohydrates))")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(.blue)
                    Text("g carbs")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color(.systemBlue).opacity(0.1))
                .cornerRadius(8)
            }
            
            // Portion details
            VStack(alignment: .leading, spacing: 6) {
                if !foodItem.portionEstimate.isEmpty {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Portion:")
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundColor(.secondary)
                        Text(foodItem.portionEstimate)
                            .font(.caption)
                            .foregroundColor(.primary)
                    }
                }
                
                if let usdaSize = foodItem.usdaServingSize, !usdaSize.isEmpty {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("USDA Serving:")
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundColor(.secondary)
                        HStack {
                            Text(usdaSize)
                                .font(.caption)
                                .foregroundColor(.primary)
                            Text("(×\(String(format: "%.1f", foodItem.servingMultiplier)))")
                                .font(.caption)
                                .foregroundColor(.orange)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, 24) // Align with food name
            
            // Additional nutrition if available
            if let protein = foodItem.protein, let fat = foodItem.fat, let calories = foodItem.calories {
                HStack(spacing: 12) {
                    Spacer()
                    
                    // Protein
                    if protein > 0 {
                        VStack(spacing: 2) {
                            Text("\(String(format: "%.1f", protein))")
                                .font(.caption)
                                .fontWeight(.medium)
                                .foregroundColor(.red)
                            Text("protein")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    // Fat
                    if fat > 0 {
                        VStack(spacing: 2) {
                            Text("\(String(format: "%.1f", fat))")
                                .font(.caption)
                                .fontWeight(.medium)
                                .foregroundColor(.orange)
                            Text("fat")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    // Calories
                    if calories > 0 {
                        VStack(spacing: 2) {
                            Text("\(String(format: "%.0f", calories))")
                                .font(.caption)
                                .fontWeight(.medium)
                                .foregroundColor(.green)
                            Text("cal")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Color(.systemGray6))
                .cornerRadius(8)
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(Color(.systemBackground))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color(.systemGray4), lineWidth: 1)
        )
    }
}
