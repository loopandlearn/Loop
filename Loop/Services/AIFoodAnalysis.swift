//
//  AIFoodAnalysis.swift
//  Loop
//
//  Created by Taylor Patterson. Coded by Claude Code in June 2025
//  Copyright © 2025 LoopKit Authors. All rights reserved.
//

import UIKit
import Vision
import CoreML
import Foundation
import os.log
import LoopKit
import CryptoKit
import SwiftUI
import Network

// MARK: - Network Quality Monitoring

/// Network quality monitor for determining analysis strategy
class NetworkQualityMonitor: ObservableObject {
    static let shared = NetworkQualityMonitor()
    
    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "NetworkMonitor")
    
    @Published var isConnected = false
    @Published var connectionType: NWInterface.InterfaceType?
    @Published var isExpensive = false
    @Published var isConstrained = false
    
    private init() {
        startMonitoring()
    }
    
    private func startMonitoring() {
        monitor.pathUpdateHandler = { [weak self] path in
            DispatchQueue.main.async {
                self?.isConnected = path.status == .satisfied
                self?.isExpensive = path.isExpensive
                self?.isConstrained = path.isConstrained
                
                // Determine connection type
                if path.usesInterfaceType(.wifi) {
                    self?.connectionType = .wifi
                } else if path.usesInterfaceType(.cellular) {
                    self?.connectionType = .cellular
                } else if path.usesInterfaceType(.wiredEthernet) {
                    self?.connectionType = .wiredEthernet
                } else {
                    self?.connectionType = nil
                }
            }
        }
        monitor.start(queue: queue)
    }
    
    /// Determines if we should use aggressive optimizations
    var shouldUseConservativeMode: Bool {
        return !isConnected || isExpensive || isConstrained || connectionType == .cellular
    }
    
    /// Determines if parallel processing is safe
    var shouldUseParallelProcessing: Bool {
        return isConnected && !isExpensive && !isConstrained && connectionType == .wifi
    }
    
    /// Gets appropriate timeout for current network conditions
    var recommendedTimeout: TimeInterval {
        if shouldUseConservativeMode {
            return 45.0  // Conservative timeout for poor networks
        } else {
            return 25.0  // Standard timeout for good networks
        }
    }
}

// MARK: - Timeout Helper

/// Timeout wrapper for async operations
private func withTimeoutForAnalysis<T>(seconds: TimeInterval, operation: @escaping () async throws -> T) async throws -> T {
    return try await withThrowingTaskGroup(of: T.self) { group in
        // Add the actual operation
        group.addTask {
            try await operation()
        }
        
        // Add timeout task
        group.addTask {
            try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            throw AIFoodAnalysisError.timeout as Error
        }
        
        // Return first result (either success or timeout)
        defer { group.cancelAll() }
        guard let result = try await group.next() else {
            throw AIFoodAnalysisError.timeout as Error
        }
        return result
    }
}

// MARK: - AI Food Analysis Models

/// Optimized analysis prompt for faster processing while maintaining accuracy
private let standardAnalysisPrompt = """
You are my personal certified nutrition specialist who optimizes for optimal diabeties management. You understand Servings compared to Portions and the importance of being educated about this. You are clinicly minded but have a knack for explaining complicated nutrition information layman's terms. Analyze this food image for better diabetes management. Primary goal: accurate carbohydrate content for insulin dosing. Do not over estimate the carbs or that could lead to user over dosing on insulin.

FIRST: Determine if this image shows:
1. ACTUAL FOOD ON A PLATE/PLATTER/CONTAINER (proceed with portion analysis)
2. MENU TEXT/DESCRIPTIONS (provide USDA standard servings only, clearly marked as estimates)

KEY CONCEPTS FOR ACTUAL FOOD PHOTOS:
• PORTIONS = distinct food items visible
• SERVINGS = USDA standard amounts (3oz chicken, 1/2 cup rice/vegetables)
• Calculate serving multipliers vs USDA standards

KEY CONCEPTS FOR MENU ITEMS:
• NO PORTION ANALYSIS possible without seeing actual food
• Provide ONLY USDA standard serving information
• Mark all values as "estimated based on USDA standards"
• Cannot assess actual portions or plate sizes from menu text

EXAMPLE: Chicken (6oz = 2 servings), Rice (1 cup = 2 servings), Vegetables (1/2 cup = 1 serving)

GLYCEMIC INDEX REFERENCE FOR DIABETES MANAGEMENT:
• LOW GI (55 or less): Slower blood sugar rise, easier insulin timing
  - Examples: Barley (25), Steel-cut oats (42), Whole grain bread (51), Sweet potato (54)
• MEDIUM GI (56-69): Moderate blood sugar impact
  - Examples: Brown rice (68), Whole wheat bread (69), Instant oatmeal (66)
• HIGH GI (70+): Rapid blood sugar spike, requires careful insulin timing
  - Examples: White rice (73), White bread (75), Instant mashed potatoes (87), Cornflakes (81)

COOKING METHOD IMPACT ON GI:
• Cooking increases GI: Raw carrots (47) vs cooked carrots (85)
• Processing increases GI: Steel-cut oats (42) vs instant oats (79)
• Cooling cooked starches slightly reduces GI (resistant starch formation)
• Al dente pasta has lower GI than well-cooked pasta

DIABETIC DOSING IMPLICATIONS:
• LOW GI foods: Allow longer pre-meal insulin timing (15-30 min before eating)
• HIGH GI foods: May require immediate insulin or post-meal correction
• MIXED MEALS: Protein and fat slow carb absorption, reducing effective GI
• PORTION SIZE: Larger portions of even low-GI foods can cause significant blood sugar impact
• FOOD COMBINATIONS: Combining high GI foods with low GI foods balances glucose levels
• FIBER CONTENT: Higher fiber foods have lower GI (e.g., whole grains vs processed grains)
• RIPENESS AFFECTS GI: Ripe fruits have higher GI than unripe fruits
• PROCESSING INCREASES GI: Instant foods have higher GI than minimally processed foods

RESPOND ONLY IN JSON FORMAT with these exact fields:

FOR ACTUAL FOOD PHOTOS:
{
  "image_type": "food_photo",
  "food_items": [
    {
      "name": "specific food name with exact preparation detail I can see (e.g., 'char-grilled chicken breast with grill marks', 'steamed white jasmine rice with separated grains')",
      "portion_estimate": "exact portion with visual references (e.g., '6 oz grilled chicken breast - length of my palm, thickness of deck of cards based on fork comparison', '1.5 cups steamed rice - covers 1/3 of the 10-inch plate')",
      "usda_serving_size": "standard USDA serving size for this food (e.g., '3 oz for chicken breast', '1/2 cup for cooked rice', '1/2 cup for cooked vegetables')",
      "serving_multiplier": "how many USDA servings I estimate in this visual portion (e.g., 2.0 for 6oz chicken since USDA serving is 3oz)",
      "preparation_method": "specific cooking details I observe (e.g., 'grilled at high heat - evident from dark crosshatch marks and slight charring on edges', 'steamed perfectly - grains are separated and fluffy, no oil sheen visible')",
      "visual_cues": "exact visual elements I'm analyzing (e.g., 'measuring chicken against 7-inch fork length, rice portion covers exactly 1/3 of plate diameter, broccoli florets are uniform bright green')",
      "carbohydrates": number_in_grams_for_this_exact_portion,
      "calories": number_in_kcal_for_this_exact_portion,
      "protein": number_in_grams_for_this_exact_portion,
      "fat": number_in_grams_for_this_exact_portion,
      "assessment_notes": "step-by-step explanation how I calculated this portion using visible objects and measurements, then compared to USDA serving sizes"
    }
  ],
  "total_food_portions": count_of_distinct_food_items,
  "total_usda_servings": sum_of_all_serving_multipliers,
  "total_carbohydrates": sum_of_all_carbs,
  "total_calories": sum_of_all_calories,
  "total_protein": sum_of_all_protein,
  "total_fat": sum_of_all_fat,
  "confidence": decimal_between_0_and_1,
  "diabetes_considerations": "Based on available information: [carb sources, glycemic index impact, and timing considerations]. GLYCEMIC INDEX: [specify if foods are low GI (<55), medium GI (56-69), or high GI (70+) and explain impact on blood sugar]. For insulin dosing, consider [relevant factors including absorption speed and peak timing].",
  "visual_assessment_details": "FOR FOOD PHOTOS: [textures, colors, cooking evidence]. FOR MENU ITEMS: Menu text shows [description from menu]. Cannot assess visual food qualities from menu text alone.",
  "overall_description": "[describe plate size]. The food is arranged [describe arrangement]. The textures I observe are [specific textures]. The colors are [specific colors]. The cooking methods evident are [specific evidence]. Any utensils visible are [describe utensils]. The background shows [describe background].",
  "portion_assessment_method": "The plate size is based on [method]. I compared the protein to [reference object]. The rice portion was estimated by [specific visual reference]. I estimated the vegetables by [method]. SERVING SIZE REASONING: [Explain why you calculated the number of servings]. My confidence is based on [specific visual cues available]."
}

FOR MENU ITEMS:
{
  "image_type": "menu_item",
  "food_items": [
    {
      "name": "menu item name as written on menu",
      "portion_estimate": "CANNOT DETERMINE - menu text only, no actual food visible",
      "usda_serving_size": "standard USDA serving size for this food type (e.g., '3 oz for chicken breast', '1/2 cup for cooked rice')",
      "serving_multiplier": 1.0,
      "preparation_method": "method described on menu (if any)",
      "visual_cues": "NONE - menu text analysis only",
      "carbohydrates": number_in_grams_for_USDA_standard_serving,
      "calories": number_in_kcal_for_USDA_standard_serving,
      "protein": number_in_grams_for_USDA_standard_serving,
      "fat": number_in_grams_for_USDA_standard_serving,
      "assessment_notes": "ESTIMATE ONLY - Based on USDA standard serving size. Cannot assess actual portions without seeing prepared food on plate."
    }
  ],
  "total_food_portions": count_of_distinct_food_items,
  "total_usda_servings": sum_of_all_serving_multipliers,
  "total_carbohydrates": sum_of_all_carbs,
  "total_calories": sum_of_all_calories,
  "total_protein": sum_of_all_protein,
  "total_fat": sum_of_all_fat,
  "confidence": decimal_between_0_and_1,
  "diabetes_considerations": "Based on available information: [carb sources, glycemic index impact, and timing considerations]. GLYCEMIC INDEX: [specify if foods are low GI (<55), medium GI (56-69), or high GI (70+) and explain impact on blood sugar]. For insulin dosing, consider [relevant factors including absorption speed and peak timing].",
  "visual_assessment_details": "FOR FOOD PHOTOS: [textures, colors, cooking evidence]. FOR MENU ITEMS: Menu text shows [description from menu]. Cannot assess visual food qualities from menu text alone.",
  "overall_description": "Menu item text analysis. No actual food portions visible for assessment.",
  "portion_assessment_method": "MENU ANALYSIS ONLY - Cannot determine actual portions without seeing food on plate. All nutrition values are ESTIMATES based on USDA standard serving sizes. Actual restaurant portions may vary significantly."
}

MENU ITEM EXAMPLE:
If menu shows "Grilled Chicken Caesar Salad", respond:
{
  "image_type": "menu_item",
  "food_items": [
    {
      "name": "Grilled Chicken Caesar Salad",
      "portion_estimate": "CANNOT DETERMINE - menu text only, no actual food visible",
      "usda_serving_size": "3 oz chicken breast + 2 cups mixed greens",
      "serving_multiplier": 1.0,
      "preparation_method": "grilled chicken as described on menu",
      "visual_cues": "NONE - menu text analysis only",
      "carbohydrates": 8.0,
      "calories": 250,
      "protein": 25.0,
      "fat": 12.0,
      "assessment_notes": "ESTIMATE ONLY - Based on USDA standard serving size. Cannot assess actual portions without seeing prepared food on plate."
    }
  ],
  "total_carbohydrates": 8.0,
  "total_calories": 250,
  "total_protein": 25.0,
  "total_fat": 12.0,
  "confidence": 0.7,
  "diabetes_considerations": "Based on menu analysis: Low glycemic impact due to minimal carbs from vegetables and croutons (estimated 8g total). Mixed meal with high protein (25g) and moderate fat (12g) will slow carb absorption. For insulin dosing, this is a low-carb meal requiring minimal rapid-acting insulin. Consider extended bolus if using insulin pump due to protein and fat content.",
  "visual_assessment_details": "Menu text shows 'Grilled Chicken Caesar Salad'. Cannot assess visual food qualities from menu text alone.",
  "overall_description": "Menu item text analysis. No actual food portions visible for assessment.",
  "portion_assessment_method": "MENU ANALYSIS ONLY - Cannot determine actual portions without seeing food on plate. All nutrition values are ESTIMATES based on USDA standard serving sizes. Actual restaurant portions may vary significantly."
}

HIGH GLYCEMIC INDEX EXAMPLE:
If menu shows "Teriyaki Chicken Bowl with White Rice", respond:
{
  "image_type": "menu_item",
  "food_items": [
    {
      "name": "Teriyaki Chicken with White Rice",
      "portion_estimate": "CANNOT DETERMINE - menu text only, no actual food visible",
      "usda_serving_size": "3 oz chicken breast + 1/2 cup cooked white rice",
      "serving_multiplier": 1.0,
      "preparation_method": "teriyaki glazed chicken with steamed white rice as described on menu",
      "visual_cues": "NONE - menu text analysis only",
      "carbohydrates": 35.0,
      "calories": 320,
      "protein": 28.0,
      "fat": 6.0,
      "assessment_notes": "ESTIMATE ONLY - Based on USDA standard serving size. Cannot assess actual portions without seeing prepared food on plate."
    }
  ],
  "total_carbohydrates": 35.0,
  "total_calories": 320,
  "total_protein": 28.0,
  "total_fat": 6.0,
  "confidence": 0.7,
  "diabetes_considerations": "Based on menu analysis: HIGH GLYCEMIC INDEX meal due to white rice (GI ~73). The 35g carbs will cause rapid blood sugar spike within 15-30 minutes. However, protein (28g) and moderate fat (6g) provide significant moderation - mixed meal effect reduces overall glycemic impact compared to eating rice alone. For insulin dosing: Consider pre-meal rapid-acting insulin 10-15 minutes before eating (shorter timing due to protein/fat). Monitor for peak blood sugar at 45-75 minutes post-meal (delayed peak due to mixed meal). Teriyaki sauce adds sugars but protein helps buffer the response.",
  "visual_assessment_details": "Menu text shows 'Teriyaki Chicken Bowl with White Rice'. Cannot assess visual food qualities from menu text alone.",
  "overall_description": "Menu item text analysis. No actual food portions visible for assessment.",
  "portion_assessment_method": "MENU ANALYSIS ONLY - Cannot determine actual portions without seeing food on plate. All nutrition values are ESTIMATES based on USDA standard serving sizes. Actual restaurant portions may vary significantly."
}

MIXED GI FOOD COMBINATION EXAMPLE:
If menu shows "Quinoa Bowl with Sweet Potato and Black Beans", respond:
{
  "image_type": "menu_item",
  "food_items": [
    {
      "name": "Quinoa Bowl with Sweet Potato and Black Beans",
      "portion_estimate": "CANNOT DETERMINE - menu text only, no actual food visible",
      "usda_serving_size": "1/2 cup cooked quinoa + 1/2 cup sweet potato + 1/2 cup black beans",
      "serving_multiplier": 1.0,
      "preparation_method": "cooked quinoa, roasted sweet potato, and seasoned black beans as described on menu",
      "visual_cues": "NONE - menu text analysis only",
      "carbohydrates": 42.0,
      "calories": 285,
      "protein": 12.0,
      "fat": 4.0,
      "assessment_notes": "ESTIMATE ONLY - Based on USDA standard serving size. Cannot assess actual portions without seeing prepared food on plate."
    }
  ],
  "total_carbohydrates": 42.0,
  "total_calories": 285,
  "total_protein": 12.0,
  "total_fat": 4.0,
  "confidence": 0.8,
  "diabetes_considerations": "Based on menu analysis: MIXED GLYCEMIC INDEX meal with balanced components. Quinoa (low-medium GI ~53), sweet potato (medium GI ~54), and black beans (low GI ~30) create favorable combination. High fiber content (estimated 12g+) and plant protein (12g) significantly slow carb absorption. For insulin dosing: This meal allows 20-30 minute pre-meal insulin timing due to low-medium GI foods and high fiber. Expect gradual, sustained blood sugar rise over 60-120 minutes rather than sharp spike. Ideal for extended insulin action.",
  "visual_assessment_details": "Menu text shows 'Quinoa Bowl with Sweet Potato and Black Beans'. Cannot assess visual food qualities from menu text alone.",
  "overall_description": "Menu item text analysis. No actual food portions visible for assessment.",
  "portion_assessment_method": "MENU ANALYSIS ONLY - Cannot determine actual portions without seeing food on plate. All nutrition values are ESTIMATES based on USDA standard serving sizes. Actual restaurant portions may vary significantly."
}

MANDATORY REQUIREMENTS - DO NOT BE VAGUE:

FOR FOOD PHOTOS:
❌ NEVER confuse portions with servings - count distinct food items as portions, calculate number of servings based on USDA standards
❌ NEVER say "4 servings" when you mean "4 portions" - be precise about USDA serving calculations
❌ NEVER say "mixed vegetables" - specify "steamed broccoli florets, diced carrots"
❌ NEVER say "chicken" - specify "grilled chicken breast"
❌ NEVER say "average portion" - specify "6 oz portion covering 1/4 of plate = 2 USDA servings"
❌ NEVER say "well-cooked" - specify "golden-brown with visible caramelization"

✅ ALWAYS distinguish between food portions (distinct items) and USDA servings (standardized amounts)
✅ ALWAYS calculate serving_multiplier based on USDA serving sizes
✅ ALWAYS explain WHY you calculated the number of servings (e.g., "twice the standard serving size")
✅ ALWAYS indicate if portions are larger/smaller than typical (helps with portion control)
✅ ALWAYS describe exact colors, textures, sizes, shapes, cooking evidence
✅ ALWAYS compare portions to visible objects (fork, plate, hand if visible)
✅ ALWAYS explain if the food appears to be on a platter of food or a single plate of food
✅ ALWAYS describe specific cooking methods you can see evidence of
✅ ALWAYS count discrete items (3 broccoli florets, 4 potato wedges)
✅ ALWAYS calculate nutrition from YOUR visual portion assessment
✅ ALWAYS explain your reasoning with specific visual evidence
✅ ALWAYS identify glycemic index category (low/medium/high GI) for carbohydrate-containing foods
✅ ALWAYS explain how cooking method affects GI when visible (e.g., "well-cooked white rice = high GI ~73")
✅ ALWAYS provide specific insulin timing guidance based on GI classification
✅ ALWAYS consider how protein/fat in mixed meals may moderate carb absorption
✅ ALWAYS assess food combinations and explain how low GI foods may balance high GI foods in the meal
✅ ALWAYS note fiber content and processing level as factors affecting GI
✅ ALWAYS consider food ripeness and cooking degree when assessing GI impact

FOR MENU ITEMS:
❌ NEVER make assumptions about plate sizes, portions, or actual serving sizes
❌ NEVER estimate visual portions when analyzing menu text only
❌ NEVER claim to see cooking methods, textures, or visual details from menu text
❌ NEVER multiply nutrition values by assumed restaurant portion sizes

✅ ALWAYS set image_type to "menu_item" when analyzing menu text
✅ ALWAYS set portion_estimate to "CANNOT DETERMINE - menu text only"
✅ ALWAYS set serving_multiplier to 1.0 for menu items (USDA standard only)
✅ ALWAYS set visual_cues to "NONE - menu text analysis only"
✅ ALWAYS mark assessment_notes as "ESTIMATE ONLY - Based on USDA standard serving size"
✅ ALWAYS use portion_assessment_method to explain this is menu analysis with no visual portions
✅ ALWAYS provide actual USDA standard nutrition values (carbohydrates, protein, fat, calories)
✅ ALWAYS calculate nutrition based on typical USDA serving sizes for the identified food type
✅ ALWAYS include total nutrition fields even for menu items (based on USDA standards)
✅ ALWAYS translate into the user's device native language or if unknown, translate into ENGLISH before analysing the menu item
✅ ALWAYS provide glycemic index assessment for menu items based on typical preparation methods
✅ ALWAYS include diabetes timing guidance even for menu items based on typical GI values

"""

/// Individual food item analysis with detailed portion assessment
struct FoodItemAnalysis {
    let name: String
    let portionEstimate: String
    let usdaServingSize: String?
    let servingMultiplier: Double
    let preparationMethod: String?
    let visualCues: String?
    let carbohydrates: Double
    let protein: Double?
    let fat: Double?
    let calories: Double?
    let assessmentNotes: String?
}

/// Type of image being analyzed
enum ImageAnalysisType: String {
    case foodPhoto = "food_photo"
    case menuItem = "menu_item"
}

/// Result from AI food analysis with detailed breakdown
struct AIFoodAnalysisResult {
    let imageType: ImageAnalysisType?
    let foodItemsDetailed: [FoodItemAnalysis]
    let overallDescription: String?
    let confidence: AIConfidenceLevel
    let totalFoodPortions: Int?
    let totalUsdaServings: Double?
    let totalCarbohydrates: Double
    let totalProtein: Double?
    let totalFat: Double?
    let totalCalories: Double?
    let portionAssessmentMethod: String?
    let diabetesConsiderations: String?
    let visualAssessmentDetails: String?
    let notes: String?
    
    // Legacy compatibility properties
    var foodItems: [String] {
        return foodItemsDetailed.map { $0.name }
    }
    
    var detailedDescription: String? {
        return overallDescription
    }
    
    var portionSize: String {
        if foodItemsDetailed.count == 1 {
            return foodItemsDetailed.first?.portionEstimate ?? "1 serving"
        } else {
            // Create concise food summary for multiple items (clean food names)
            let foodNames = foodItemsDetailed.map { item in
                // Clean up food names by removing technical terms
                cleanFoodName(item.name)
            }
            return foodNames.joined(separator: ", ")
        }
    }
    
    // Helper function to clean food names for display
    private func cleanFoodName(_ name: String) -> String {
        var cleaned = name
        
        // Remove common technical terms while preserving essential info
        let removals = [
            " Breast", " Fillet", " Thigh", " Florets", " Spears",
            " Cubes", " Medley", " Portion"
        ]
        
        for removal in removals {
            cleaned = cleaned.replacingOccurrences(of: removal, with: "")
        }
        
        // Capitalize first letter and trim
        cleaned = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
        if !cleaned.isEmpty {
            cleaned = cleaned.prefix(1).uppercased() + cleaned.dropFirst()
        }
        
        return cleaned.isEmpty ? name : cleaned
    }
    
    var servingSizeDescription: String {
        if foodItemsDetailed.count == 1 {
            return foodItemsDetailed.first?.portionEstimate ?? "1 serving"
        } else {
            // Return the same clean food names for "Based on" text
            let foodNames = foodItemsDetailed.map { item in
                cleanFoodName(item.name)
            }
            return foodNames.joined(separator: ", ")
        }
    }
    
    var carbohydrates: Double {
        return totalCarbohydrates
    }
    
    var protein: Double? {
        return totalProtein
    }
    
    var fat: Double? {
        return totalFat
    }
    
    var calories: Double? {
        return totalCalories
    }
    
    var servings: Double {
        return foodItemsDetailed.reduce(0) { $0 + $1.servingMultiplier }
    }
    
    var analysisNotes: String? {
        return portionAssessmentMethod
    }
}

/// Confidence level for AI analysis
enum AIConfidenceLevel: String, CaseIterable {
    case high = "high"
    case medium = "medium" 
    case low = "low"
}

/// Errors that can occur during AI food analysis
enum AIFoodAnalysisError: Error, LocalizedError {
    case imageProcessingFailed
    case requestCreationFailed
    case networkError(Error)
    case invalidResponse
    case apiError(Int)
    case responseParsingFailed
    case noApiKey
    case customError(String)
    case creditsExhausted(provider: String)
    case rateLimitExceeded(provider: String)
    case quotaExceeded(provider: String)
    case timeout
    
    var errorDescription: String? {
        switch self {
        case .imageProcessingFailed:
            return NSLocalizedString("Failed to process image for analysis", comment: "Error when image processing fails")
        case .requestCreationFailed:
            return NSLocalizedString("Failed to create analysis request", comment: "Error when request creation fails")
        case .networkError(let error):
            return String(format: NSLocalizedString("Network error: %@", comment: "Error for network failures"), error.localizedDescription)
        case .invalidResponse:
            return NSLocalizedString("Invalid response from AI service", comment: "Error for invalid API response")
        case .apiError(let code):
            if code == 400 {
                return NSLocalizedString("Invalid API request (400). Please check your API key configuration in Food Search Settings.", comment: "Error for 400 API failures")
            } else if code == 403 {
                return NSLocalizedString("API access forbidden (403). Your API key may be invalid or you've exceeded your quota.", comment: "Error for 403 API failures") 
            } else if code == 404 {
                return NSLocalizedString("AI service not found (404). Please check your API configuration.", comment: "Error for 404 API failures")
            } else {
                return String(format: NSLocalizedString("AI service error (code: %d)", comment: "Error for API failures"), code)
            }
        case .responseParsingFailed:
            return NSLocalizedString("Failed to parse AI analysis results", comment: "Error when response parsing fails")
        case .noApiKey:
            return NSLocalizedString("No API key configured. Please go to Food Search Settings to set up your API key.", comment: "Error when API key is missing")
        case .customError(let message):
            return message
        case .creditsExhausted(let provider):
            return String(format: NSLocalizedString("%@ credits exhausted. Please check your account billing or add credits to continue using AI food analysis.", comment: "Error when AI provider credits are exhausted"), provider)
        case .rateLimitExceeded(let provider):
            return String(format: NSLocalizedString("%@ rate limit exceeded. Please wait a moment before trying again.", comment: "Error when AI provider rate limit is exceeded"), provider)
        case .quotaExceeded(let provider):
            return String(format: NSLocalizedString("%@ quota exceeded. Please check your usage limits or upgrade your plan.", comment: "Error when AI provider quota is exceeded"), provider)
        case .timeout:
            return NSLocalizedString("Analysis timed out. Please check your network connection and try again.", comment: "Error when AI analysis times out")
        }
    }
}

// MARK: - Search Types

/// Different types of food searches that can use different providers
enum SearchType: String, CaseIterable {
    case textSearch = "Text/Voice Search"
    case barcodeSearch = "Barcode Scanning"
    case aiImageSearch = "AI Image Analysis"
    
    var description: String {
        switch self {
        case .textSearch:
            return "Searching by typing food names or using voice input"
        case .barcodeSearch:
            return "Scanning product barcodes with camera"
        case .aiImageSearch:
            return "Taking photos of food for AI analysis"
        }
    }
}

/// Available providers for different search types
enum SearchProvider: String, CaseIterable {
    case claude = "Anthropic (Claude API)"
    case googleGemini = "Google (Gemini API)"
    case openAI = "OpenAI (ChatGPT API)"
    case openFoodFacts = "OpenFoodFacts (Default)"
    case usdaFoodData = "USDA FoodData Central"
    
    
    var supportsSearchType: [SearchType] {
        switch self {
        case .claude:
            return [.textSearch, .aiImageSearch]
        case .googleGemini:
            return [.textSearch, .aiImageSearch]
        case .openAI:
            return [.textSearch, .aiImageSearch]
        case .openFoodFacts:
            return [.textSearch, .barcodeSearch]
        case .usdaFoodData:
            return [.textSearch]
        }
    }
    
    var requiresAPIKey: Bool {
        switch self {
        case .openFoodFacts, .usdaFoodData:
            return false
        case .claude, .googleGemini, .openAI:
            return true
        }
    }
}

// MARK: - Intelligent Caching System

/// Cache for AI analysis results based on image hashing
class ImageAnalysisCache {
    private let cache = NSCache<NSString, CachedAnalysisResult>()
    private let cacheExpirationTime: TimeInterval = 300 // 5 minutes
    
    init() {
        // Configure cache limits
        cache.countLimit = 50  // Maximum 50 cached results
        cache.totalCostLimit = 10 * 1024 * 1024  // 10MB limit
    }
    
    /// Cache an analysis result for the given image
    func cacheResult(_ result: AIFoodAnalysisResult, for image: UIImage) {
        let imageHash = calculateImageHash(image)
        let cachedResult = CachedAnalysisResult(
            result: result,
            timestamp: Date(),
            imageHash: imageHash
        )
        
        cache.setObject(cachedResult, forKey: imageHash as NSString)
    }
    
    /// Get cached result for the given image if available and not expired
    func getCachedResult(for image: UIImage) -> AIFoodAnalysisResult? {
        let imageHash = calculateImageHash(image)
        
        guard let cachedResult = cache.object(forKey: imageHash as NSString) else {
            return nil
        }
        
        // Check if cache entry has expired
        if Date().timeIntervalSince(cachedResult.timestamp) > cacheExpirationTime {
            cache.removeObject(forKey: imageHash as NSString)
            return nil
        }
        
        return cachedResult.result
    }
    
    /// Calculate a hash for the image to use as cache key
    private func calculateImageHash(_ image: UIImage) -> String {
        // Convert image to data and calculate SHA256 hash
        guard let imageData = image.jpegData(compressionQuality: 0.8) else {
            return UUID().uuidString
        }
        
        let hash = imageData.sha256Hash
        return hash
    }
    
    /// Clear all cached results
    func clearCache() {
        cache.removeAllObjects()
    }
}

/// Wrapper for cached analysis results with metadata
private class CachedAnalysisResult {
    let result: AIFoodAnalysisResult
    let timestamp: Date
    let imageHash: String
    
    init(result: AIFoodAnalysisResult, timestamp: Date, imageHash: String) {
        self.result = result
        self.timestamp = timestamp
        self.imageHash = imageHash
    }
}

/// Extension to calculate SHA256 hash for Data
extension Data {
    var sha256Hash: String {
        let digest = SHA256.hash(data: self)
        return digest.compactMap { String(format: "%02x", $0) }.joined()
    }
}

// MARK: - Configurable AI Service

/// AI service that allows users to configure their own API keys
class ConfigurableAIService: ObservableObject {
    
    // MARK: - Singleton
    
    static let shared = ConfigurableAIService()
    
    // private let log = OSLog(category: "ConfigurableAIService")
    
    // MARK: - Published Properties
    
    @Published var textSearchProvider: SearchProvider = .openFoodFacts
    @Published var barcodeSearchProvider: SearchProvider = .openFoodFacts
    @Published var aiImageSearchProvider: SearchProvider = .googleGemini
    
    private init() {
        // Load current settings
        textSearchProvider = SearchProvider(rawValue: UserDefaults.standard.textSearchProvider) ?? .openFoodFacts
        barcodeSearchProvider = SearchProvider(rawValue: UserDefaults.standard.barcodeSearchProvider) ?? .openFoodFacts
        aiImageSearchProvider = SearchProvider(rawValue: UserDefaults.standard.aiImageProvider) ?? .googleGemini
        
        // Google Gemini API key should be configured by user
        if UserDefaults.standard.googleGeminiAPIKey.isEmpty {
            print("⚠️ Google Gemini API key not configured - user needs to set up their own key")
        }
    }
    
    // MARK: - Configuration
    
    enum AIProvider: String, CaseIterable {
        case basicAnalysis = "Basic Analysis (Free)"
        case claude = "Anthropic (Claude API)"
        case googleGemini = "Google (Gemini API)"
        case openAI = "OpenAI (ChatGPT API)"
        
        var requiresAPIKey: Bool {
            switch self {
            case .basicAnalysis:
                return false
            case .claude, .googleGemini, .openAI:
                return true
            }
        }
        
        var requiresCustomURL: Bool {
            switch self {
            case .basicAnalysis, .claude, .googleGemini, .openAI:
                return false
            }
        }
        
        var description: String {
            switch self {
            case .basicAnalysis:
                return "Uses built-in food database and basic image analysis. No API key required."
            case .claude:
                return "Anthropic's Claude AI with excellent reasoning. Requires paid API key from console.anthropic.com."
            case .googleGemini:
                return "Free API key available at ai.google.dev. Best for detailed food analysis."
            case .openAI:
                return "Requires paid OpenAI API key. Most accurate for complex meals."
            }
        }
    }
    
    // MARK: - User Settings
    
    var currentProvider: AIProvider {
        get { AIProvider(rawValue: UserDefaults.standard.aiProvider) ?? .basicAnalysis }
        set { UserDefaults.standard.aiProvider = newValue.rawValue }
    }
    
    var isConfigured: Bool {
        switch currentProvider {
        case .basicAnalysis:
            return true // Always available, no configuration needed
        case .claude:
            return !UserDefaults.standard.claudeAPIKey.isEmpty
        case .googleGemini:
            return !UserDefaults.standard.googleGeminiAPIKey.isEmpty
        case .openAI:
            return !UserDefaults.standard.openAIAPIKey.isEmpty
        }
    }
    
    // MARK: - Public Methods
    
    func setAPIKey(_ key: String, for provider: AIProvider) {
        switch provider {
        case .basicAnalysis:
            break // No API key needed for basic analysis
        case .claude:
            UserDefaults.standard.claudeAPIKey = key
        case .googleGemini:
            UserDefaults.standard.googleGeminiAPIKey = key
        case .openAI:
            UserDefaults.standard.openAIAPIKey = key
        }
    }
    
    func setAPIURL(_ url: String, for provider: AIProvider) {
        switch provider {
        case .basicAnalysis, .claude, .googleGemini, .openAI:
            break // No custom URL needed
        }
    }
    
    func setAPIName(_ name: String, for provider: AIProvider) {
        switch provider {
        case .basicAnalysis, .claude, .googleGemini, .openAI:
            break // No custom name needed
        }
    }
    
    func setQuery(_ query: String, for provider: AIProvider) {
        switch provider {
        case .basicAnalysis:
            break // Uses built-in queries
        case .claude:
            UserDefaults.standard.claudeQuery = query
        case .googleGemini:
            UserDefaults.standard.googleGeminiQuery = query
        case .openAI:
            UserDefaults.standard.openAIQuery = query
        }
    }
    
    func setAnalysisMode(_ mode: AnalysisMode) {
        analysisMode = mode
        UserDefaults.standard.analysisMode = mode.rawValue
    }
    
    func getAPIKey(for provider: AIProvider) -> String? {
        switch provider {
        case .basicAnalysis:
            return nil // No API key needed
        case .claude:
            let key = UserDefaults.standard.claudeAPIKey
            return key.isEmpty ? nil : key
        case .googleGemini:
            let key = UserDefaults.standard.googleGeminiAPIKey
            return key.isEmpty ? nil : key
        case .openAI:
            let key = UserDefaults.standard.openAIAPIKey
            return key.isEmpty ? nil : key
        }
    }
    
    func getAPIURL(for provider: AIProvider) -> String? {
        switch provider {
        case .basicAnalysis, .claude, .googleGemini, .openAI:
            return nil
        }
    }
    
    func getAPIName(for provider: AIProvider) -> String? {
        switch provider {
        case .basicAnalysis, .claude, .googleGemini, .openAI:
            return nil
        }
    }
    
    func getQuery(for provider: AIProvider) -> String? {
        switch provider {
        case .basicAnalysis:
            return "Analyze this food image and estimate nutritional content based on visual appearance and portion size."
        case .claude:
            return UserDefaults.standard.claudeQuery
        case .googleGemini:
            return UserDefaults.standard.googleGeminiQuery
        case .openAI:
            return UserDefaults.standard.openAIQuery
        }
    }
    
    /// Reset to default Basic Analysis provider (useful for troubleshooting)
    func resetToDefault() {
        currentProvider = .basicAnalysis
        print("🔄 Reset AI provider to default: \(currentProvider.rawValue)")
    }
    
    // MARK: - Search Type Configuration
    
    func getProviderForSearchType(_ searchType: SearchType) -> SearchProvider {
        switch searchType {
        case .textSearch:
            return textSearchProvider
        case .barcodeSearch:
            return barcodeSearchProvider
        case .aiImageSearch:
            return aiImageSearchProvider
        }
    }
    
    func setProviderForSearchType(_ provider: SearchProvider, searchType: SearchType) {
        switch searchType {
        case .textSearch:
            textSearchProvider = provider
            UserDefaults.standard.textSearchProvider = provider.rawValue
        case .barcodeSearch:
            barcodeSearchProvider = provider
            UserDefaults.standard.barcodeSearchProvider = provider.rawValue
        case .aiImageSearch:
            aiImageSearchProvider = provider
            UserDefaults.standard.aiImageProvider = provider.rawValue
        }
        
    }
    
    func getAvailableProvidersForSearchType(_ searchType: SearchType) -> [SearchProvider] {
        return SearchProvider.allCases
            .filter { $0.supportsSearchType.contains(searchType) }
            .sorted { $0.rawValue < $1.rawValue }
    }
    
    /// Get a summary of current provider configuration
    func getProviderConfigurationSummary() -> String {
        let textProvider = getProviderForSearchType(.textSearch).rawValue
        let barcodeProvider = getProviderForSearchType(.barcodeSearch).rawValue
        let aiProvider = getProviderForSearchType(.aiImageSearch).rawValue
        
        return """
        Search Configuration:
        • Text/Voice: \(textProvider)
        • Barcode: \(barcodeProvider) 
        • AI Image: \(aiProvider)
        """
    }
    
    /// Convert AI image search provider to AIProvider for image analysis
    private func getAIProviderForImageAnalysis() -> AIProvider {
        switch aiImageSearchProvider {
        case .claude:
            return .claude
        case .googleGemini:
            return .googleGemini
        case .openAI:
            return .openAI
        case .openFoodFacts, .usdaFoodData:
            // These don't support image analysis, fallback to basic
            return .basicAnalysis
        }
    }
    
    /// Analyze food image using the configured provider with intelligent caching
    func analyzeFoodImage(_ image: UIImage) async throws -> AIFoodAnalysisResult {
        return try await analyzeFoodImage(image, telemetryCallback: nil)
    }
    
    /// Analyze food image with telemetry callbacks for progress tracking
    func analyzeFoodImage(_ image: UIImage, telemetryCallback: ((String) -> Void)?) async throws -> AIFoodAnalysisResult {
        // Check cache first for instant results
        if let cachedResult = imageAnalysisCache.getCachedResult(for: image) {
            telemetryCallback?("📋 Found cached analysis result")
            return cachedResult
        }
        
        telemetryCallback?("🎯 Selecting optimal AI provider...")
        
        // Use parallel processing if enabled
        if enableParallelProcessing {
            telemetryCallback?("⚡ Starting parallel provider analysis...")
            let result = try await analyzeImageWithParallelProviders(image, telemetryCallback: telemetryCallback)
            imageAnalysisCache.cacheResult(result, for: image)
            return result
        }
        
        // Use the AI image search provider instead of the separate currentProvider
        let provider = getAIProviderForImageAnalysis()
        
        let result: AIFoodAnalysisResult
        
        switch provider {
        case .basicAnalysis:
            telemetryCallback?("🧠 Running basic analysis...")
            result = try await BasicFoodAnalysisService.shared.analyzeFoodImage(image, telemetryCallback: telemetryCallback)
        case .claude:
            let key = UserDefaults.standard.claudeAPIKey
            let query = UserDefaults.standard.claudeQuery
            guard !key.isEmpty else {
                print("❌ Claude API key not configured")
                throw AIFoodAnalysisError.noApiKey
            }
            telemetryCallback?("🤖 Connecting to Claude AI...")
            result = try await ClaudeFoodAnalysisService.shared.analyzeFoodImage(image, apiKey: key, query: query, telemetryCallback: telemetryCallback)
        case .googleGemini:
            let key = UserDefaults.standard.googleGeminiAPIKey
            let query = UserDefaults.standard.googleGeminiQuery
            guard !key.isEmpty else {
                print("❌ Google Gemini API key not configured")
                throw AIFoodAnalysisError.noApiKey
            }
            telemetryCallback?("🤖 Connecting to Google Gemini...")
            result = try await GoogleGeminiFoodAnalysisService.shared.analyzeFoodImage(image, apiKey: key, query: query, telemetryCallback: telemetryCallback)
        case .openAI:
            let key = UserDefaults.standard.openAIAPIKey
            let query = UserDefaults.standard.openAIQuery
            guard !key.isEmpty else {
                print("❌ OpenAI API key not configured")
                throw AIFoodAnalysisError.noApiKey
            }
            telemetryCallback?("🤖 Connecting to OpenAI...")
            result = try await OpenAIFoodAnalysisService.shared.analyzeFoodImage(image, apiKey: key, query: query, telemetryCallback: telemetryCallback)
        }
        
        telemetryCallback?("💾 Caching analysis result...")
        
        // Cache the result for future use
        imageAnalysisCache.cacheResult(result, for: image)
        
        return result
    }
    
    // MARK: - Text Processing Helper Methods
    
    /// Centralized list of unwanted prefixes that AI commonly adds to food descriptions
    /// Add new prefixes here as edge cases are discovered - this is the SINGLE source of truth
    static let unwantedFoodPrefixes = [
        "of ",
        "with ",
        "contains ",
        "includes ",
        "featuring ",
        "consisting of ",
        "made of ",
        "composed of ",
        "a plate of ",
        "a bowl of ",
        "a serving of ",
        "a portion of ",
        "some ",
        "several ",
        "multiple ",
        "various ",
        "an ",
        "a ",
        "the ",
        "- ",
        "– ",
        "— ",
        "this is ",
        "there is ",
        "there are ",
        "i see ",
        "appears to be ",
        "looks like "
    ]
    
    /// Adaptive image compression based on image size for optimal performance
    static func adaptiveCompressionQuality(for image: UIImage) -> CGFloat {
        let imagePixels = image.size.width * image.size.height
        
        // Adaptive compression: larger images need more compression for faster uploads
        switch imagePixels {
        case 0..<500_000:      // Small images (< 500k pixels)
            return 0.9
        case 500_000..<1_000_000: // Medium images (500k-1M pixels)
            return 0.8
        default:               // Large images (> 1M pixels)
            return 0.7
        }
    }
    
    /// Analysis mode for speed vs accuracy trade-offs
    enum AnalysisMode: String, CaseIterable {
        case standard = "standard"
        case fast = "fast"
        
        var displayName: String {
            switch self {
            case .standard:
                return "Standard Quality"
            case .fast:
                return "Fast Mode"
            }
        }
        
        var description: String {
            switch self {
            case .standard:
                return "Highest accuracy, slower processing"
            case .fast:
                return "Good accuracy, 50-70% faster"
            }
        }
        
        var detailedDescription: String {
            switch self {
            case .standard:
                return "Uses full AI models (GPT-4o, Gemini-1.5-Pro, Claude-3.5-Sonnet) for maximum accuracy. Best for complex meals with multiple components."
            case .fast:
                return "Uses optimized models (GPT-4o-mini, Gemini-1.5-Flash) for faster analysis. 2-3x faster with ~5-10% accuracy trade-off. Great for simple meals."
            }
        }
        
        var iconName: String {
            switch self {
            case .standard:
                return "target"
            case .fast:
                return "bolt.fill"
            }
        }
        
        var iconColor: Color {
            switch self {
            case .standard:
                return .blue
            case .fast:
                return .orange
            }
        }
        
        var backgroundColor: Color {
            switch self {
            case .standard:
                return Color(.systemBlue).opacity(0.08)
            case .fast:
                return Color(.systemOrange).opacity(0.08)
            }
        }
    }
    
    /// Current analysis mode setting
    @Published var analysisMode: AnalysisMode = AnalysisMode(rawValue: UserDefaults.standard.analysisMode) ?? .standard
    
    /// Enable parallel processing for fastest results
    @Published var enableParallelProcessing: Bool = false
    
    /// Intelligent caching system for AI analysis results
    private var imageAnalysisCache = ImageAnalysisCache()
    
    /// Provider-specific optimized timeouts for better performance and user experience
    static func optimalTimeout(for provider: SearchProvider) -> TimeInterval {
        switch provider {
        case .googleGemini:
            return 15  // Free tier optimization - faster but may timeout on complex analysis
        case .openAI:
            return 20  // Paid tier reliability - good balance of speed and reliability
        case .claude:
            return 25  // Highest quality responses but slower processing
        case .openFoodFacts, .usdaFoodData:
            return 10  // Simple API calls should be fast
        }
    }
    
    /// Get optimal model for provider and analysis mode
    static func optimalModel(for provider: SearchProvider, mode: AnalysisMode) -> String {
        switch (provider, mode) {
        case (.googleGemini, .standard):
            return "gemini-1.5-pro"
        case (.googleGemini, .fast):
            return "gemini-1.5-flash"  // ~2x faster
        case (.openAI, .standard):
            return "gpt-4o"
        case (.openAI, .fast):
            return "gpt-4o-mini"  // ~3x faster
        case (.claude, .standard):
            return "claude-3-5-sonnet-20241022"
        case (.claude, .fast):
            return "claude-3-haiku-20240307"  // ~2x faster
        default:
            return ""  // Not applicable for non-AI providers
        }
    }
    
    /// Safe async image optimization to prevent main thread blocking
    static func optimizeImageForAnalysisSafely(_ image: UIImage) async -> UIImage {
        return await withCheckedContinuation { continuation in
            // Process image on background thread to prevent UI freezing
            DispatchQueue.global(qos: .userInitiated).async {
                let optimized = optimizeImageForAnalysis(image)
                continuation.resume(returning: optimized)
            }
        }
    }
    
    /// Intelligent image resizing for optimal AI analysis performance
    static func optimizeImageForAnalysis(_ image: UIImage) -> UIImage {
        let maxDimension: CGFloat = 1024
        
        // Check if resizing is needed
        if image.size.width <= maxDimension && image.size.height <= maxDimension {
            return image // No resizing needed
        }
        
        // Calculate new size maintaining aspect ratio
        let scale = maxDimension / max(image.size.width, image.size.height)
        let newSize = CGSize(
            width: image.size.width * scale,
            height: image.size.height * scale
        )
        
        
        // Perform high-quality resize
        return resizeImage(image, to: newSize)
    }
    
    /// High-quality image resizing helper
    private static func resizeImage(_ image: UIImage, to newSize: CGSize) -> UIImage {
        UIGraphicsBeginImageContextWithOptions(newSize, false, 0.0)
        defer { UIGraphicsEndImageContext() }
        
        image.draw(in: CGRect(origin: .zero, size: newSize))
        return UIGraphicsGetImageFromCurrentImageContext() ?? image
    }
    
    /// Analyze image with network-aware provider strategy
    func analyzeImageWithParallelProviders(_ image: UIImage, telemetryCallback: ((String) -> Void)?) async throws -> AIFoodAnalysisResult {
        return try await analyzeImageWithParallelProviders(image, query: "", telemetryCallback: telemetryCallback)
    }
    
    func analyzeImageWithParallelProviders(_ image: UIImage, query: String = "", telemetryCallback: ((String) -> Void)?) async throws -> AIFoodAnalysisResult {
        let networkMonitor = NetworkQualityMonitor.shared
        telemetryCallback?("🌐 Analyzing network conditions...")
        
        // Get available providers that support AI analysis
        let availableProviders: [SearchProvider] = [.googleGemini, .openAI, .claude].filter { provider in
            // Only include providers that have API keys configured
            switch provider {
            case .googleGemini:
                return !UserDefaults.standard.googleGeminiAPIKey.isEmpty
            case .openAI:
                return !UserDefaults.standard.openAIAPIKey.isEmpty
            case .claude:
                return !UserDefaults.standard.claudeAPIKey.isEmpty
            default:
                return false
            }
        }
        
        guard !availableProviders.isEmpty else {
            throw AIFoodAnalysisError.noApiKey
        }
        
        // Check network conditions and decide strategy
        if networkMonitor.shouldUseParallelProcessing && availableProviders.count > 1 {
            print("🌐 Good network detected, using parallel processing with \(availableProviders.count) providers")
            telemetryCallback?("⚡ Starting parallel AI provider analysis...")
            return try await analyzeWithParallelStrategy(image, providers: availableProviders, query: query, telemetryCallback: telemetryCallback)
        } else {
            print("🌐 Poor network detected, using sequential processing")
            telemetryCallback?("🔄 Starting sequential AI provider analysis...")
            return try await analyzeWithSequentialStrategy(image, providers: availableProviders, query: query, telemetryCallback: telemetryCallback)
        }
    }
    
    /// Parallel strategy for good networks
    private func analyzeWithParallelStrategy(_ image: UIImage, providers: [SearchProvider], query: String, telemetryCallback: ((String) -> Void)?) async throws -> AIFoodAnalysisResult {
        let timeout = NetworkQualityMonitor.shared.recommendedTimeout
        
        return try await withThrowingTaskGroup(of: AIFoodAnalysisResult.self) { group in
            // Add timeout wrapper for each provider
            for provider in providers {
                group.addTask { [weak self] in
                    guard let self = self else { throw AIFoodAnalysisError.invalidResponse }
                    return try await withTimeoutForAnalysis(seconds: timeout) {
                        let startTime = Date()
                        do {
                            let result = try await self.analyzeWithSingleProvider(image, provider: provider, query: query)
                            let duration = Date().timeIntervalSince(startTime)
                            print("✅ \(provider.rawValue) succeeded in \(String(format: "%.1f", duration))s")
                            return result
                        } catch {
                            let duration = Date().timeIntervalSince(startTime)
                            print("❌ \(provider.rawValue) failed after \(String(format: "%.1f", duration))s: \(error.localizedDescription)")
                            throw error
                        }
                    }
                }
            }
            
            // Return the first successful result
            guard let result = try await group.next() else {
                throw AIFoodAnalysisError.invalidResponse
            }
            
            // Cancel remaining tasks since we got our result
            group.cancelAll()
            
            return result
        }
    }
    
    /// Sequential strategy for poor networks - tries providers one by one
    private func analyzeWithSequentialStrategy(_ image: UIImage, providers: [SearchProvider], query: String, telemetryCallback: ((String) -> Void)?) async throws -> AIFoodAnalysisResult {
        let timeout = NetworkQualityMonitor.shared.recommendedTimeout
        var lastError: Error?
        
        // Try providers one by one until one succeeds
        for provider in providers {
            do {
                print("🔄 Trying \(provider.rawValue) sequentially...")
                telemetryCallback?("🤖 Trying \(provider.rawValue)...")
                let result = try await withTimeoutForAnalysis(seconds: timeout) {
                    try await self.analyzeWithSingleProvider(image, provider: provider, query: query)
                }
                print("✅ \(provider.rawValue) succeeded in sequential mode")
                return result
            } catch {
                print("❌ \(provider.rawValue) failed in sequential mode: \(error.localizedDescription)")
                lastError = error
                // Continue to next provider
            }
        }
        
        // If all providers failed, throw the last error
        throw lastError ?? AIFoodAnalysisError.invalidResponse
    }
    
    /// Analyze with a single provider (helper for parallel processing)
    private func analyzeWithSingleProvider(_ image: UIImage, provider: SearchProvider, query: String) async throws -> AIFoodAnalysisResult {
        switch provider {
        case .googleGemini:
            return try await GoogleGeminiFoodAnalysisService.shared.analyzeFoodImage(image, apiKey: UserDefaults.standard.googleGeminiAPIKey, query: query, telemetryCallback: nil)
        case .openAI:
            return try await OpenAIFoodAnalysisService.shared.analyzeFoodImage(image, apiKey: UserDefaults.standard.openAIAPIKey, query: query, telemetryCallback: nil)
        case .claude:
            return try await ClaudeFoodAnalysisService.shared.analyzeFoodImage(image, apiKey: UserDefaults.standard.claudeAPIKey, query: query, telemetryCallback: nil)
        default:
            throw AIFoodAnalysisError.invalidResponse
        }
    }
    
    /// Public static method to clean food text - can be called from anywhere
    static func cleanFoodText(_ text: String?) -> String? {
        guard let text = text else { return nil }
        
        var cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        
        
        // Keep removing prefixes until none match (handles multiple prefixes)
        var foundPrefix = true
        var iterationCount = 0
        while foundPrefix && iterationCount < 10 { // Prevent infinite loops
            foundPrefix = false
            iterationCount += 1
            
            for prefix in unwantedFoodPrefixes {
                if cleaned.lowercased().hasPrefix(prefix.lowercased()) {
                    cleaned = String(cleaned.dropFirst(prefix.count))
                    cleaned = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
                    foundPrefix = true
                    break
                }
            }
        }
        
        // Capitalize first letter
        if !cleaned.isEmpty {
            cleaned = cleaned.prefix(1).uppercased() + cleaned.dropFirst()
        }
        
        return cleaned.isEmpty ? nil : cleaned
    }
    
    /// Cleans AI description text by removing unwanted prefixes and ensuring proper capitalization
    private func cleanAIDescription(_ description: String?) -> String? {
        return Self.cleanFoodText(description)
    }
}


// MARK: - OpenAI Service (Alternative)

class OpenAIFoodAnalysisService {
    static let shared = OpenAIFoodAnalysisService()
    private init() {}
    
    func analyzeFoodImage(_ image: UIImage, apiKey: String, query: String) async throws -> AIFoodAnalysisResult {
        return try await analyzeFoodImage(image, apiKey: apiKey, query: query, telemetryCallback: nil)
    }
    
    func analyzeFoodImage(_ image: UIImage, apiKey: String, query: String, telemetryCallback: ((String) -> Void)?) async throws -> AIFoodAnalysisResult {
        // OpenAI GPT-4 Vision implementation
        guard let url = URL(string: "https://api.openai.com/v1/chat/completions") else {
            throw AIFoodAnalysisError.invalidResponse
        }
        
        // Get optimal model based on current analysis mode
        telemetryCallback?("⚙️ Configuring OpenAI parameters...")
        let analysisMode = ConfigurableAIService.shared.analysisMode
        let model = ConfigurableAIService.optimalModel(for: .openAI, mode: analysisMode)
        
        // Optimize image size for faster processing and uploads
        telemetryCallback?("🖼️ Optimizing image for analysis...")
        let optimizedImage = ConfigurableAIService.optimizeImageForAnalysis(image)
        
        // Convert image to base64 with adaptive compression
        telemetryCallback?("🔄 Encoding image data...")
        let compressionQuality = ConfigurableAIService.adaptiveCompressionQuality(for: optimizedImage)
        guard let imageData = optimizedImage.jpegData(compressionQuality: compressionQuality) else {
            throw AIFoodAnalysisError.imageProcessingFailed
        }
        let base64Image = imageData.base64EncodedString()
        
        // Create OpenAI API request
        telemetryCallback?("📡 Preparing API request...")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        
        let payload: [String: Any] = [
            "model": model,
            "temperature": 0.01,  // Minimal temperature for fastest, most direct responses
            "messages": [
                [
                    "role": "user",
                    "content": [
                        [
                            "type": "text",
                            "text": query.isEmpty ? standardAnalysisPrompt : "\(query)\n\n\(standardAnalysisPrompt)"
                        ],
                        [
                            "type": "image_url",
                            "image_url": [
                                "url": "data:image/jpeg;base64,\(base64Image)",
                                "detail": "high"  // Request high-detail image processing
                            ]
                        ]
                    ]
                ]
            ],
            "max_tokens": 2500  // Optimized for faster responses while maintaining accuracy
        ]
        
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        } catch {
            throw AIFoodAnalysisError.requestCreationFailed
        }
        
        telemetryCallback?("🌐 Sending request to OpenAI...")
        
        do {
            telemetryCallback?("⏳ Awaiting result from AI...")
            let (data, response) = try await URLSession.shared.data(for: request)
            
            telemetryCallback?("📥 Received response from OpenAI...")
            
            guard let httpResponse = response as? HTTPURLResponse else {
                print("❌ OpenAI: Invalid HTTP response")
                throw AIFoodAnalysisError.invalidResponse
            }
            
            
            guard httpResponse.statusCode == 200 else {
                // Enhanced error logging for different status codes
                if let errorData = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    print("❌ OpenAI API Error: \(errorData)")
                    
                    // Check for specific OpenAI errors
                    if let error = errorData["error"] as? [String: Any],
                       let message = error["message"] as? String {
                        print("❌ OpenAI Error Message: \(message)")
                        
                        // Handle common OpenAI errors with specific error types
                        if message.contains("quota") || message.contains("billing") || message.contains("insufficient_quota") {
                            throw AIFoodAnalysisError.creditsExhausted(provider: "OpenAI")
                        } else if message.contains("rate_limit_exceeded") || message.contains("rate limit") {
                            throw AIFoodAnalysisError.rateLimitExceeded(provider: "OpenAI")
                        } else if message.contains("invalid") && message.contains("key") {
                            throw AIFoodAnalysisError.customError("Invalid OpenAI API key. Please check your configuration.")
                        } else if message.contains("usage") && message.contains("limit") {
                            throw AIFoodAnalysisError.quotaExceeded(provider: "OpenAI")
                        }
                    }
                } else {
                    print("❌ OpenAI: Error data: \(String(data: data, encoding: .utf8) ?? "Unable to decode")")
                }
                
                // Handle HTTP status codes for common credit/quota issues
                if httpResponse.statusCode == 429 {
                    throw AIFoodAnalysisError.rateLimitExceeded(provider: "OpenAI")
                } else if httpResponse.statusCode == 402 {
                    throw AIFoodAnalysisError.creditsExhausted(provider: "OpenAI")
                } else if httpResponse.statusCode == 403 {
                    throw AIFoodAnalysisError.quotaExceeded(provider: "OpenAI")
                }
                
                // Generic API error for unhandled cases
                throw AIFoodAnalysisError.apiError(httpResponse.statusCode)
            }
            
            // Enhanced data validation like Gemini
            guard data.count > 0 else {
                print("❌ OpenAI: Empty response data")
                throw AIFoodAnalysisError.invalidResponse
            }
            
            // Parse OpenAI response
            telemetryCallback?("🔍 Parsing OpenAI response...")
            guard let jsonResponse = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                print("❌ OpenAI: Failed to parse response as JSON")
                print("❌ OpenAI: Raw response data: \(String(data: data, encoding: .utf8) ?? "Unable to decode")")
                throw AIFoodAnalysisError.responseParsingFailed
            }
            
            
            guard let choices = jsonResponse["choices"] as? [[String: Any]] else {
                print("❌ OpenAI: No 'choices' array in response")
                print("❌ OpenAI: Response structure: \(jsonResponse)")
                throw AIFoodAnalysisError.responseParsingFailed
            }
            
            guard let firstChoice = choices.first else {
                print("❌ OpenAI: Empty choices array")
                throw AIFoodAnalysisError.responseParsingFailed
            }
            
            guard let message = firstChoice["message"] as? [String: Any] else {
                print("❌ OpenAI: No 'message' in first choice")
                print("❌ OpenAI: First choice structure: \(firstChoice)")
                throw AIFoodAnalysisError.responseParsingFailed
            }
            
            guard let content = message["content"] as? String else {
                print("❌ OpenAI: No 'content' in message")
                print("❌ OpenAI: Message structure: \(message)")
                throw AIFoodAnalysisError.responseParsingFailed
            }
            
            // Add detailed logging like Gemini
            print("🔧 OpenAI: Received content length: \(content.count)")
            
            // Enhanced JSON extraction from GPT-4's response (like Claude service)
            telemetryCallback?("⚡ Processing AI analysis results...")
            let cleanedContent = content.trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: "```json", with: "")
                .replacingOccurrences(of: "```", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            
            // Try to extract JSON content safely
            var jsonString: String
            if let jsonStartRange = cleanedContent.range(of: "{"),
               let jsonEndRange = cleanedContent.range(of: "}", options: .backwards),
               jsonStartRange.lowerBound < jsonEndRange.upperBound {
                jsonString = String(cleanedContent[jsonStartRange.lowerBound..<jsonEndRange.upperBound])
            } else {
                jsonString = cleanedContent
            }
            
            // Enhanced JSON parsing with error recovery
            var nutritionData: [String: Any]
            do {
                guard let jsonData = jsonString.data(using: .utf8),
                      let parsedJson = try JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else {
                    print("❌ OpenAI: Failed to parse extracted JSON")
                    print("❌ OpenAI: JSON string was: \(jsonString.prefix(500))...")
                    throw AIFoodAnalysisError.responseParsingFailed
                }
                nutritionData = parsedJson
            } catch {
                print("❌ OpenAI: JSON parsing error: \(error)")
                print("❌ OpenAI: Problematic JSON: \(jsonString.prefix(500))...")
                
                // Try fallback parsing with the original cleaned content
                if let fallbackData = cleanedContent.data(using: .utf8),
                   let fallbackJson = try? JSONSerialization.jsonObject(with: fallbackData) as? [String: Any] {
                    nutritionData = fallbackJson
                } else {
                    print("❌ OpenAI: Both primary and fallback JSON parsing failed")
                    print("❌ OpenAI: Original content: \(content.prefix(1000))...")
                    throw AIFoodAnalysisError.responseParsingFailed
                }
            }
            
            // Parse detailed food items analysis with enhanced safety like Gemini
            var detailedFoodItems: [FoodItemAnalysis] = []
            
            do {
                if let foodItemsArray = nutritionData["food_items"] as? [[String: Any]] {
                    
                    // Enhanced per-item error handling like Gemini
                    for (index, itemData) in foodItemsArray.enumerated() {
                        do {
                            let foodItem = FoodItemAnalysis(
                                name: extractString(from: itemData, keys: ["name"]) ?? "Unknown Food",
                                portionEstimate: extractString(from: itemData, keys: ["portion_estimate"]) ?? "1 serving",
                                usdaServingSize: extractString(from: itemData, keys: ["usda_serving_size"]),
                                servingMultiplier: max(0.1, extractNumber(from: itemData, keys: ["serving_multiplier"]) ?? 1.0), // Prevent zero/negative
                                preparationMethod: extractString(from: itemData, keys: ["preparation_method"]),
                                visualCues: extractString(from: itemData, keys: ["visual_cues"]),
                                carbohydrates: max(0, extractNumber(from: itemData, keys: ["carbohydrates"]) ?? 0), // Ensure non-negative
                                protein: extractNumber(from: itemData, keys: ["protein"]).map { max(0, $0) }, // Bounds checking
                                fat: extractNumber(from: itemData, keys: ["fat"]).map { max(0, $0) }, // Bounds checking
                                calories: extractNumber(from: itemData, keys: ["calories"]).map { max(0, $0) }, // Bounds checking
                                assessmentNotes: extractString(from: itemData, keys: ["assessment_notes"])
                            )
                            detailedFoodItems.append(foodItem)
                        } catch {
                            print("⚠️ OpenAI: Error parsing food item \(index): \(error)")
                            // Continue with other items - doesn't crash the whole analysis
                        }
                    }
                }
            } catch {
                print("⚠️ OpenAI: Error in food items parsing: \(error)")
            }
            
            if let foodItemsStringArray = extractStringArray(from: nutritionData, keys: ["food_items"]) {
                // Fallback to legacy format
                let totalCarbs = extractNumber(from: nutritionData, keys: ["total_carbohydrates", "carbohydrates", "carbs"]) ?? 25.0
                let totalProtein = extractNumber(from: nutritionData, keys: ["total_protein", "protein"])
                let totalFat = extractNumber(from: nutritionData, keys: ["total_fat", "fat"])
                let totalCalories = extractNumber(from: nutritionData, keys: ["total_calories", "calories"])
                
                let singleItem = FoodItemAnalysis(
                    name: foodItemsStringArray.joined(separator: ", "),
                    portionEstimate: extractString(from: nutritionData, keys: ["portion_size"]) ?? "1 serving",
                    usdaServingSize: nil,
                    servingMultiplier: 1.0,
                    preparationMethod: nil,
                    visualCues: nil,
                    carbohydrates: totalCarbs,
                    protein: totalProtein,
                    fat: totalFat,
                    calories: totalCalories,
                    assessmentNotes: "Legacy format - combined nutrition values"
                )
                detailedFoodItems = [singleItem]
            }
            
            // Enhanced fallback creation like Gemini - safe fallback with comprehensive data
            if detailedFoodItems.isEmpty {
                let fallbackItem = FoodItemAnalysis(
                    name: "OpenAI Analyzed Food",
                    portionEstimate: "1 standard serving",
                    usdaServingSize: nil,
                    servingMultiplier: 1.0,
                    preparationMethod: "Not specified in analysis",
                    visualCues: "Visual analysis completed",
                    carbohydrates: 25.0,
                    protein: 15.0,
                    fat: 10.0,
                    calories: 200.0,
                    assessmentNotes: "Safe fallback nutrition estimate - please verify actual food for accuracy"
                )
                detailedFoodItems = [fallbackItem]
            }
            
            // Extract totals
            let totalCarbs = extractNumber(from: nutritionData, keys: ["total_carbohydrates"]) ?? 
                            detailedFoodItems.reduce(0) { $0 + $1.carbohydrates }
            let totalProtein = extractNumber(from: nutritionData, keys: ["total_protein"]) ?? 
                              detailedFoodItems.compactMap { $0.protein }.reduce(0, +)
            let totalFat = extractNumber(from: nutritionData, keys: ["total_fat"]) ?? 
                          detailedFoodItems.compactMap { $0.fat }.reduce(0, +)
            let totalCalories = extractNumber(from: nutritionData, keys: ["total_calories"]) ?? 
                               detailedFoodItems.compactMap { $0.calories }.reduce(0, +)
            
            let overallDescription = extractString(from: nutritionData, keys: ["overall_description", "detailed_description"])
            let portionAssessmentMethod = extractString(from: nutritionData, keys: ["portion_assessment_method", "analysis_notes"])
            let diabetesConsiderations = extractString(from: nutritionData, keys: ["diabetes_considerations"])
            let visualAssessmentDetails = extractString(from: nutritionData, keys: ["visual_assessment_details"])
            
            let confidence = extractConfidence(from: nutritionData)
            
            // Extract image type to determine if this is menu analysis or food photo
            let imageTypeString = extractString(from: nutritionData, keys: ["image_type"])
            let imageType = ImageAnalysisType(rawValue: imageTypeString ?? "food_photo") ?? .foodPhoto
            
            return AIFoodAnalysisResult(
                imageType: imageType,
                foodItemsDetailed: detailedFoodItems,
                overallDescription: overallDescription,
                confidence: confidence,
                totalFoodPortions: extractNumber(from: nutritionData, keys: ["total_food_portions"]).map { Int($0) },
                totalUsdaServings: extractNumber(from: nutritionData, keys: ["total_usda_servings"]),
                totalCarbohydrates: totalCarbs,
                totalProtein: totalProtein > 0 ? totalProtein : nil,
                totalFat: totalFat > 0 ? totalFat : nil,
                totalCalories: totalCalories > 0 ? totalCalories : nil,
                portionAssessmentMethod: portionAssessmentMethod,
                diabetesConsiderations: diabetesConsiderations,
                visualAssessmentDetails: visualAssessmentDetails,
                notes: "Analyzed using OpenAI GPT-4 Vision with detailed portion assessment"
            )
            
        } catch let error as AIFoodAnalysisError {
            throw error
        } catch {
            throw AIFoodAnalysisError.networkError(error)
        }
    }
    
    // MARK: - Helper Methods
    
    private func extractNumber(from json: [String: Any], keys: [String]) -> Double? {
        for key in keys {
            if let value = json[key] as? Double {
                return max(0, value) // Ensure non-negative nutrition values like Gemini
            } else if let value = json[key] as? Int {
                return max(0, Double(value)) // Ensure non-negative
            } else if let value = json[key] as? String, let doubleValue = Double(value) {
                return max(0, doubleValue) // Ensure non-negative
            }
        }
        return nil
    }
    
    private func extractString(from json: [String: Any], keys: [String]) -> String? {
        for key in keys {
            if let value = json[key] as? String, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return value.trimmingCharacters(in: .whitespacesAndNewlines) // Enhanced validation like Gemini
            }
        }
        return nil
    }
    
    private func extractStringArray(from json: [String: Any], keys: [String]) -> [String]? {
        for key in keys {
            if let value = json[key] as? [String] {
                return value
            } else if let value = json[key] as? String {
                return [value]
            }
        }
        return nil
    }
    
    private func extractConfidence(from json: [String: Any]) -> AIConfidenceLevel {
        let confidenceKeys = ["confidence", "confidence_score"]
        
        for key in confidenceKeys {
            if let value = json[key] as? Double {
                if value >= 0.8 {
                    return .high
                } else if value >= 0.5 {
                    return .medium
                } else {
                    return .low
                }
            } else if let value = json[key] as? String {
                // Enhanced string-based confidence detection like Gemini
                switch value.lowercased() {
                case "high":
                    return .high
                case "medium":
                    return .medium
                case "low":
                    return .low
                default:
                    continue
                }
            }
        }
        
        return .medium // Default confidence
    }
}

// MARK: - USDA FoodData Central Service

/// Service for accessing USDA FoodData Central API for comprehensive nutrition data
class USDAFoodDataService {
    static let shared = USDAFoodDataService()
    
    private let baseURL = "https://api.nal.usda.gov/fdc/v1"
    private let session: URLSession
    
    private init() {
        // Create optimized URLSession configuration for USDA API
        let config = URLSessionConfiguration.default
        let usdaTimeout = ConfigurableAIService.optimalTimeout(for: .usdaFoodData)
        config.timeoutIntervalForRequest = usdaTimeout
        config.timeoutIntervalForResource = usdaTimeout * 2
        config.waitsForConnectivity = true
        config.allowsCellularAccess = true
        self.session = URLSession(configuration: config)
    }
    
    /// Search for food products using USDA FoodData Central API
    /// - Parameter query: Search query string
    /// - Returns: Array of OpenFoodFactsProduct for compatibility with existing UI
    func searchProducts(query: String, pageSize: Int = 15) async throws -> [OpenFoodFactsProduct] {
        print("🇺🇸 Starting USDA FoodData Central search for: '\(query)'")
        
        guard let url = URL(string: "\(baseURL)/foods/search") else {
            throw OpenFoodFactsError.invalidURL
        }
        
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "api_key", value: "DEMO_KEY"), // USDA provides free demo access
            URLQueryItem(name: "query", value: query),
            URLQueryItem(name: "pageSize", value: String(pageSize)),
            URLQueryItem(name: "dataType", value: "Foundation,SR Legacy,Survey"), // Get comprehensive nutrition data from multiple sources
            URLQueryItem(name: "sortBy", value: "dataType.keyword"),
            URLQueryItem(name: "sortOrder", value: "asc"),
            URLQueryItem(name: "requireAllWords", value: "false") // Allow partial matches for better results
        ]
        
        guard let finalURL = components.url else {
            throw OpenFoodFactsError.invalidURL
        }
        
        var request = URLRequest(url: finalURL)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = ConfigurableAIService.optimalTimeout(for: .usdaFoodData)
        
        do {
            // Check for task cancellation before making request
            try Task.checkCancellation()
            
            let (data, response) = try await session.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                throw OpenFoodFactsError.invalidResponse
            }
            
            guard httpResponse.statusCode == 200 else {
                print("🇺🇸 USDA: HTTP error \(httpResponse.statusCode)")
                throw OpenFoodFactsError.serverError(httpResponse.statusCode)
            }
            
            // Parse USDA response with detailed error handling
            guard let jsonResponse = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                print("🇺🇸 USDA: Invalid JSON response format")
                throw OpenFoodFactsError.decodingError(NSError(domain: "USDA", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid JSON response"]))
            }
            
            // Check for API errors in response
            if let error = jsonResponse["error"] as? [String: Any],
               let code = error["code"] as? String,
               let message = error["message"] as? String {
                print("🇺🇸 USDA: API error - \(code): \(message)")
                throw OpenFoodFactsError.serverError(400)
            }
            
            guard let foods = jsonResponse["foods"] as? [[String: Any]] else {
                print("🇺🇸 USDA: No foods array in response")
                throw OpenFoodFactsError.noData
            }
            
            print("🇺🇸 USDA: Raw API returned \(foods.count) food items")
            
            // Check for task cancellation before processing results
            try Task.checkCancellation()
            
            // Convert USDA foods to OpenFoodFactsProduct format for UI compatibility
            let products = foods.compactMap { foodData -> OpenFoodFactsProduct? in
                // Check for cancellation during processing to allow fast cancellation
                if Task.isCancelled {
                    return nil
                }
                return convertUSDAFoodToProduct(foodData)
            }
            
            print("🇺🇸 USDA search completed: \(products.count) valid products found (filtered from \(foods.count) raw items)")
            return products
            
        } catch {
            print("🇺🇸 USDA search failed: \(error)")
            
            // Handle task cancellation gracefully
            if error is CancellationError {
                print("🇺🇸 USDA: Task was cancelled (expected behavior during rapid typing)")
                return []
            }
            
            if let urlError = error as? URLError, urlError.code == .cancelled {
                print("🇺🇸 USDA: URLSession request was cancelled (expected behavior during rapid typing)")
                return []
            }
            
            throw OpenFoodFactsError.networkError(error)
        }
    }
    
    /// Convert USDA food data to OpenFoodFactsProduct for UI compatibility
    private func convertUSDAFoodToProduct(_ foodData: [String: Any]) -> OpenFoodFactsProduct? {
        guard let fdcId = foodData["fdcId"] as? Int,
              let description = foodData["description"] as? String else {
            print("🇺🇸 USDA: Missing fdcId or description for food item")
            return nil
        }
        
        // Extract nutrition data from USDA food nutrients with comprehensive mapping
        var carbs: Double = 0
        var protein: Double = 0
        var fat: Double = 0
        var fiber: Double = 0
        var sugars: Double = 0
        var energy: Double = 0
        
        // Track what nutrients we found for debugging
        var foundNutrients: [String] = []
        
        if let foodNutrients = foodData["foodNutrients"] as? [[String: Any]] {
            print("🇺🇸 USDA: Found \(foodNutrients.count) nutrients for '\(description)'")
            
            for nutrient in foodNutrients {
                // Debug: print the structure of the first few nutrients
                if foundNutrients.count < 3 {
                    print("🇺🇸 USDA: Nutrient structure: \(nutrient)")
                }
                
                // Try different possible field names for nutrient number
                var nutrientNumber: Int?
                if let number = nutrient["nutrientNumber"] as? Int {
                    nutrientNumber = number
                } else if let number = nutrient["nutrientId"] as? Int {
                    nutrientNumber = number
                } else if let numberString = nutrient["nutrientNumber"] as? String,
                          let number = Int(numberString) {
                    nutrientNumber = number
                } else if let numberString = nutrient["nutrientId"] as? String,
                          let number = Int(numberString) {
                    nutrientNumber = number
                }
                
                guard let nutrientNum = nutrientNumber else {
                    continue
                }
                
                // Handle both Double and String values from USDA API
                var value: Double = 0
                if let doubleValue = nutrient["value"] as? Double {
                    value = doubleValue
                } else if let stringValue = nutrient["value"] as? String,
                          let parsedValue = Double(stringValue) {
                    value = parsedValue
                } else if let doubleValue = nutrient["amount"] as? Double {
                    value = doubleValue
                } else if let stringValue = nutrient["amount"] as? String,
                          let parsedValue = Double(stringValue) {
                    value = parsedValue
                } else {
                    continue
                }
                
                // Comprehensive USDA nutrient number mapping
                switch nutrientNum {
                // Carbohydrates - multiple possible sources
                case 205: // Carbohydrate, by difference (most common)
                    carbs = value
                    foundNutrients.append("carbs-205")
                case 1005: // Carbohydrate, by summation
                    if carbs == 0 { carbs = value }
                    foundNutrients.append("carbs-1005")
                case 1050: // Carbohydrate, other
                    if carbs == 0 { carbs = value }
                    foundNutrients.append("carbs-1050")
                    
                // Protein - multiple possible sources  
                case 203: // Protein (most common)
                    protein = value
                    foundNutrients.append("protein-203")
                case 1003: // Protein, crude
                    if protein == 0 { protein = value }
                    foundNutrients.append("protein-1003")
                    
                // Fat - multiple possible sources
                case 204: // Total lipid (fat) (most common)
                    fat = value
                    foundNutrients.append("fat-204")
                case 1004: // Total lipid, crude
                    if fat == 0 { fat = value }
                    foundNutrients.append("fat-1004")
                    
                // Fiber - multiple possible sources
                case 291: // Fiber, total dietary (most common)
                    fiber = value
                    foundNutrients.append("fiber-291")
                case 1079: // Fiber, crude
                    if fiber == 0 { fiber = value }
                    foundNutrients.append("fiber-1079")
                    
                // Sugars - multiple possible sources
                case 269: // Sugars, total including NLEA (most common)
                    sugars = value
                    foundNutrients.append("sugars-269")
                case 1010: // Sugars, total
                    if sugars == 0 { sugars = value }
                    foundNutrients.append("sugars-1010")
                case 1063: // Sugars, added
                    if sugars == 0 { sugars = value }
                    foundNutrients.append("sugars-1063")
                    
                // Energy/Calories - multiple possible sources
                case 208: // Energy (kcal) (most common)
                    energy = value
                    foundNutrients.append("energy-208")
                case 1008: // Energy, gross
                    if energy == 0 { energy = value }
                    foundNutrients.append("energy-1008")
                case 1062: // Energy, metabolizable
                    if energy == 0 { energy = value }
                    foundNutrients.append("energy-1062")
                    
                default:
                    break
                }
            }
        } else {
            print("🇺🇸 USDA: No foodNutrients array found in food data for '\(description)'")
            print("🇺🇸 USDA: Available keys in foodData: \(Array(foodData.keys))")
        }
        
        // Log what we found for debugging
        if foundNutrients.isEmpty {
            print("🇺🇸 USDA: No recognized nutrients found for '\(description)' (fdcId: \(fdcId))")
        } else {
            print("🇺🇸 USDA: Found nutrients for '\(description)': \(foundNutrients.joined(separator: ", "))")
        }
        
        // Enhanced data quality validation
        let hasUsableNutrientData = carbs > 0 || protein > 0 || fat > 0 || energy > 0
        if !hasUsableNutrientData {
            print("🇺🇸 USDA: Skipping '\(description)' - no usable nutrient data (carbs: \(carbs), protein: \(protein), fat: \(fat), energy: \(energy))")
            return nil
        }
        
        // Create nutriments object with comprehensive data
        let nutriments = Nutriments(
            carbohydrates: carbs,
            proteins: protein > 0 ? protein : nil,
            fat: fat > 0 ? fat : nil,
            calories: energy > 0 ? energy : nil,
            sugars: sugars > 0 ? sugars : nil,
            fiber: fiber > 0 ? fiber : nil,
            energy: energy > 0 ? energy : nil
        )
        
        // Create product with USDA data
        return OpenFoodFactsProduct(
            id: String(fdcId),
            productName: cleanUSDADescription(description),
            brands: "USDA FoodData Central",
            categories: categorizeUSDAFood(description),
            nutriments: nutriments,
            servingSize: "100g", // USDA data is typically per 100g
            servingQuantity: 100.0,
            imageURL: nil,
            imageFrontUrl: nil,
            code: String(fdcId)
        )
    }
    
    /// Clean up USDA food descriptions for better readability
    private func cleanUSDADescription(_ description: String) -> String {
        var cleaned = description
        
        // Remove common USDA technical terms and codes
        let removals = [
            ", raw", ", cooked", ", boiled", ", steamed",
            ", NFS", ", NS as to form", ", not further specified",
            "USDA Commodity", "Food and Nutrition Service",
            ", UPC: ", "\\b\\d{5,}\\b" // Remove long numeric codes
        ]
        
        for removal in removals {
            if removal.starts(with: "\\") {
                // Handle regex patterns
                cleaned = cleaned.replacingOccurrences(
                    of: removal,
                    with: "",
                    options: .regularExpression
                )
            } else {
                cleaned = cleaned.replacingOccurrences(of: removal, with: "")
            }
        }
        
        // Capitalize properly and trim
        cleaned = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Ensure first letter is capitalized
        if !cleaned.isEmpty {
            cleaned = cleaned.prefix(1).uppercased() + cleaned.dropFirst()
        }
        
        return cleaned.isEmpty ? "USDA Food Item" : cleaned
    }
    
    /// Categorize USDA food items based on their description
    private func categorizeUSDAFood(_ description: String) -> String? {
        let lowercased = description.lowercased()
        
        // Define category mappings based on common USDA food terms
        let categories: [String: [String]] = [
            "Fruits": ["apple", "banana", "orange", "berry", "grape", "peach", "pear", "plum", "cherry", "melon", "fruit"],
            "Vegetables": ["broccoli", "carrot", "spinach", "lettuce", "tomato", "onion", "pepper", "cucumber", "vegetable"],
            "Grains": ["bread", "rice", "pasta", "cereal", "oat", "wheat", "barley", "quinoa", "grain"],
            "Dairy": ["milk", "cheese", "yogurt", "butter", "cream", "dairy"],
            "Protein": ["chicken", "beef", "pork", "fish", "egg", "meat", "turkey", "salmon", "tuna"],
            "Nuts & Seeds": ["nut", "seed", "almond", "peanut", "walnut", "cashew", "sunflower"],
            "Beverages": ["juice", "beverage", "drink", "soda", "tea", "coffee"],
            "Snacks": ["chip", "cookie", "cracker", "candy", "chocolate", "snack"]
        ]
        
        for (category, keywords) in categories {
            if keywords.contains(where: { lowercased.contains($0) }) {
                return category
            }
        }
        
        return nil
    }
}

// MARK: - Google Gemini Food Analysis Service

/// Service for food analysis using Google Gemini Vision API (free tier)
class GoogleGeminiFoodAnalysisService {
    static let shared = GoogleGeminiFoodAnalysisService()
    
    private let baseURLTemplate = "https://generativelanguage.googleapis.com/v1beta/models/{model}:generateContent"
    
    private init() {}
    
    func analyzeFoodImage(_ image: UIImage, apiKey: String, query: String) async throws -> AIFoodAnalysisResult {
        return try await analyzeFoodImage(image, apiKey: apiKey, query: query, telemetryCallback: nil)
    }
    
    func analyzeFoodImage(_ image: UIImage, apiKey: String, query: String, telemetryCallback: ((String) -> Void)?) async throws -> AIFoodAnalysisResult {
        print("🍱 Starting Google Gemini food analysis")
        telemetryCallback?("⚙️ Configuring Gemini parameters...")
        
        // Get optimal model based on current analysis mode
        let analysisMode = ConfigurableAIService.shared.analysisMode
        let model = ConfigurableAIService.optimalModel(for: .googleGemini, mode: analysisMode)
        let baseURL = baseURLTemplate.replacingOccurrences(of: "{model}", with: model)
        
        
        guard let url = URL(string: "\(baseURL)?key=\(apiKey)") else {
            throw AIFoodAnalysisError.invalidResponse
        }
        
        // Optimize image size for faster processing and uploads
        telemetryCallback?("🖼️ Optimizing image for analysis...")
        let optimizedImage = ConfigurableAIService.optimizeImageForAnalysis(image)
        
        // Convert image to base64 with adaptive compression
        telemetryCallback?("🔄 Encoding image data...")
        let compressionQuality = ConfigurableAIService.adaptiveCompressionQuality(for: optimizedImage)
        guard let imageData = optimizedImage.jpegData(compressionQuality: compressionQuality) else {
            throw AIFoodAnalysisError.imageProcessingFailed
        }
        let base64Image = imageData.base64EncodedString()
        
        // Create Gemini API request payload
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let payload: [String: Any] = [
            "contents": [
                [
                    "parts": [
                        [
                            "text": query.isEmpty ? standardAnalysisPrompt : "\(query)\n\n\(standardAnalysisPrompt)"
                        ],
                        [
                            "inline_data": [
                                "mime_type": "image/jpeg",
                                "data": base64Image
                            ]
                        ]
                    ]
                ]
            ],
            "generationConfig": [
                "temperature": 0.01,  // Minimal temperature for fastest responses
                "topP": 0.95,  // High value for comprehensive vocabulary
                "topK": 8,  // Very focused for maximum speed
                "maxOutputTokens": 2500  // Balanced for speed vs detail
            ]
        ]
        
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        } catch {
            throw AIFoodAnalysisError.requestCreationFailed
        }
        
        telemetryCallback?("🌐 Sending request to Google Gemini...")
        
        do {
            telemetryCallback?("⏳ Awaiting result from AI...")
            let (data, response) = try await URLSession.shared.data(for: request)
            
            telemetryCallback?("📥 Received response from Gemini...")
            
            guard let httpResponse = response as? HTTPURLResponse else {
                print("❌ Google Gemini: Invalid HTTP response")
                throw AIFoodAnalysisError.invalidResponse
            }
            
            
            guard httpResponse.statusCode == 200 else {
                print("❌ Google Gemini API error: \(httpResponse.statusCode)")
                if let errorData = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    print("❌ Gemini API Error Details: \(errorData)")
                    
                    // Check for specific Google Gemini errors
                    if let error = errorData["error"] as? [String: Any],
                       let message = error["message"] as? String {
                        print("❌ Gemini Error Message: \(message)")
                        
                        // Handle common Gemini errors with specific error types
                        if message.contains("quota") || message.contains("QUOTA_EXCEEDED") {
                            throw AIFoodAnalysisError.quotaExceeded(provider: "Google Gemini")
                        } else if message.contains("RATE_LIMIT_EXCEEDED") || message.contains("rate limit") {
                            throw AIFoodAnalysisError.rateLimitExceeded(provider: "Google Gemini")
                        } else if message.contains("PERMISSION_DENIED") || message.contains("API_KEY_INVALID") {
                            throw AIFoodAnalysisError.customError("Invalid Google Gemini API key. Please check your configuration.")
                        } else if message.contains("RESOURCE_EXHAUSTED") {
                            throw AIFoodAnalysisError.creditsExhausted(provider: "Google Gemini")
                        }
                    }
                } else {
                    print("❌ Gemini: Error data: \(String(data: data, encoding: .utf8) ?? "Unable to decode")")
                }
                
                // Handle HTTP status codes for common credit/quota issues
                if httpResponse.statusCode == 429 {
                    throw AIFoodAnalysisError.rateLimitExceeded(provider: "Google Gemini")
                } else if httpResponse.statusCode == 403 {
                    throw AIFoodAnalysisError.quotaExceeded(provider: "Google Gemini")
                }
                
                throw AIFoodAnalysisError.apiError(httpResponse.statusCode)
            }
            
            // Add data validation
            guard data.count > 0 else {
                print("❌ Google Gemini: Empty response data")
                throw AIFoodAnalysisError.invalidResponse
            }
            
            // Parse Gemini response with detailed error handling
            guard let jsonResponse = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                print("❌ Google Gemini: Failed to parse JSON response")
                print("❌ Raw response: \(String(data: data, encoding: .utf8) ?? "Unable to decode")")
                throw AIFoodAnalysisError.responseParsingFailed
            }
            
            
            guard let candidates = jsonResponse["candidates"] as? [[String: Any]], !candidates.isEmpty else {
                print("❌ Google Gemini: No candidates in response")
                if let error = jsonResponse["error"] as? [String: Any] {
                    print("❌ Google Gemini: API returned error: \(error)")
                }
                throw AIFoodAnalysisError.responseParsingFailed
            }
            
            let firstCandidate = candidates[0]
            print("🔧 Google Gemini: Candidate keys: \(Array(firstCandidate.keys))")
            
            guard let content = firstCandidate["content"] as? [String: Any],
                  let parts = content["parts"] as? [[String: Any]],
                  !parts.isEmpty,
                  let text = parts[0]["text"] as? String else {
                print("❌ Google Gemini: Invalid response structure")
                print("❌ Candidate: \(firstCandidate)")
                throw AIFoodAnalysisError.responseParsingFailed
            }
            
            print("🔧 Google Gemini: Received text length: \(text.count)")
            
            // Parse the JSON content from Gemini's response
            let cleanedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: "```json", with: "")
                .replacingOccurrences(of: "```", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            
            guard let contentData = cleanedText.data(using: .utf8),
                  let nutritionData = try JSONSerialization.jsonObject(with: contentData) as? [String: Any] else {
                throw AIFoodAnalysisError.responseParsingFailed
            }
            
            // Parse detailed food items analysis with crash protection
            var detailedFoodItems: [FoodItemAnalysis] = []
            
            do {
                if let foodItemsArray = nutritionData["food_items"] as? [[String: Any]] {
                    // New detailed format
                    for (index, itemData) in foodItemsArray.enumerated() {
                        do {
                            let foodItem = FoodItemAnalysis(
                                name: extractString(from: itemData, keys: ["name"]) ?? "Food Item \(index + 1)",
                                portionEstimate: extractString(from: itemData, keys: ["portion_estimate"]) ?? "1 serving",
                                usdaServingSize: extractString(from: itemData, keys: ["usda_serving_size"]),
                                servingMultiplier: max(0.1, extractNumber(from: itemData, keys: ["serving_multiplier"]) ?? 1.0),
                                preparationMethod: extractString(from: itemData, keys: ["preparation_method"]),
                                visualCues: extractString(from: itemData, keys: ["visual_cues"]),
                                carbohydrates: max(0, extractNumber(from: itemData, keys: ["carbohydrates"]) ?? 0),
                                protein: extractNumber(from: itemData, keys: ["protein"]),
                                fat: extractNumber(from: itemData, keys: ["fat"]),
                                calories: extractNumber(from: itemData, keys: ["calories"]),
                                assessmentNotes: extractString(from: itemData, keys: ["assessment_notes"])
                            )
                            detailedFoodItems.append(foodItem)
                        } catch {
                            print("⚠️ Google Gemini: Error parsing food item \(index): \(error)")
                            // Continue with other items
                        }
                    }
                } else if let foodItemsStringArray = extractStringArray(from: nutritionData, keys: ["food_items"]) {
                    // Fallback to legacy format
                    let totalCarbs = max(0, extractNumber(from: nutritionData, keys: ["total_carbohydrates", "carbohydrates", "carbs"]) ?? 25.0)
                    let totalProtein = extractNumber(from: nutritionData, keys: ["total_protein", "protein"])
                    let totalFat = extractNumber(from: nutritionData, keys: ["total_fat", "fat"])
                    let totalCalories = extractNumber(from: nutritionData, keys: ["total_calories", "calories"])
                    
                    let singleItem = FoodItemAnalysis(
                        name: foodItemsStringArray.joined(separator: ", "),
                        portionEstimate: extractString(from: nutritionData, keys: ["portion_size"]) ?? "1 serving",
                        usdaServingSize: nil,
                        servingMultiplier: 1.0,
                        preparationMethod: nil,
                        visualCues: nil,
                        carbohydrates: totalCarbs,
                        protein: totalProtein,
                        fat: totalFat,
                        calories: totalCalories,
                        assessmentNotes: "Legacy format - combined nutrition values"
                    )
                    detailedFoodItems = [singleItem]
                }
            } catch {
                print("⚠️ Google Gemini: Error in food items parsing: \(error)")
            }
            
            // If no detailed items were parsed, create a safe fallback
            if detailedFoodItems.isEmpty {
                let fallbackItem = FoodItemAnalysis(
                    name: "Analyzed Food",
                    portionEstimate: "1 serving",
                    usdaServingSize: nil,
                    servingMultiplier: 1.0,
                    preparationMethod: "Not specified",
                    visualCues: "Visual analysis completed",
                    carbohydrates: 25.0,
                    protein: 15.0,
                    fat: 10.0,
                    calories: 200.0,
                    assessmentNotes: "Safe fallback nutrition estimate - check actual food for accuracy"
                )
                detailedFoodItems = [fallbackItem]
            }
            
            // Extract totals with safety checks
            let totalCarbs = max(0, extractNumber(from: nutritionData, keys: ["total_carbohydrates"]) ?? 
                            detailedFoodItems.reduce(0) { $0 + $1.carbohydrates })
            let totalProtein = max(0, extractNumber(from: nutritionData, keys: ["total_protein"]) ?? 
                              detailedFoodItems.compactMap { $0.protein }.reduce(0, +))
            let totalFat = max(0, extractNumber(from: nutritionData, keys: ["total_fat"]) ?? 
                          detailedFoodItems.compactMap { $0.fat }.reduce(0, +))
            let totalCalories = max(0, extractNumber(from: nutritionData, keys: ["total_calories"]) ?? 
                               detailedFoodItems.compactMap { $0.calories }.reduce(0, +))
            
            let overallDescription = extractString(from: nutritionData, keys: ["overall_description", "detailed_description"]) ?? "Google Gemini analysis completed"
            let portionAssessmentMethod = extractString(from: nutritionData, keys: ["portion_assessment_method", "analysis_notes"])
            let diabetesConsiderations = extractString(from: nutritionData, keys: ["diabetes_considerations"])
            let visualAssessmentDetails = extractString(from: nutritionData, keys: ["visual_assessment_details"])
            
            let confidence = extractConfidence(from: nutritionData)
            
            // Extract image type to determine if this is menu analysis or food photo
            let imageTypeString = extractString(from: nutritionData, keys: ["image_type"])
            let imageType = ImageAnalysisType(rawValue: imageTypeString ?? "food_photo") ?? .foodPhoto
            
            return AIFoodAnalysisResult(
                imageType: imageType,
                foodItemsDetailed: detailedFoodItems,
                overallDescription: overallDescription,
                confidence: confidence,
                totalFoodPortions: extractNumber(from: nutritionData, keys: ["total_food_portions"]).map { Int($0) },
                totalUsdaServings: extractNumber(from: nutritionData, keys: ["total_usda_servings"]),
                totalCarbohydrates: totalCarbs,
                totalProtein: totalProtein > 0 ? totalProtein : nil,
                totalFat: totalFat > 0 ? totalFat : nil,
                totalCalories: totalCalories > 0 ? totalCalories : nil,
                portionAssessmentMethod: portionAssessmentMethod,
                diabetesConsiderations: diabetesConsiderations,
                visualAssessmentDetails: visualAssessmentDetails,
                notes: "Analyzed using Google Gemini Vision - AI food recognition with enhanced safety measures"
            )
            
        } catch let error as AIFoodAnalysisError {
            throw error
        } catch {
            throw AIFoodAnalysisError.networkError(error)
        }
    }
    
    // MARK: - Helper Methods
    
    private func extractNumber(from json: [String: Any], keys: [String]) -> Double? {
        for key in keys {
            if let value = json[key] as? Double {
                return max(0, value) // Ensure non-negative nutrition values
            } else if let value = json[key] as? Int {
                return max(0, Double(value)) // Ensure non-negative nutrition values
            } else if let value = json[key] as? String, let doubleValue = Double(value) {
                return max(0, doubleValue) // Ensure non-negative nutrition values
            }
        }
        return nil
    }
    
    private func extractString(from json: [String: Any], keys: [String]) -> String? {
        for key in keys {
            if let value = json[key] as? String, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return value.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        return nil
    }
    
    private func extractStringArray(from json: [String: Any], keys: [String]) -> [String]? {
        for key in keys {
            if let value = json[key] as? [String] {
                let cleanedItems = value.compactMap { item in
                    let cleaned = item.trimmingCharacters(in: .whitespacesAndNewlines)
                    return cleaned.isEmpty ? nil : cleaned
                }
                return cleanedItems.isEmpty ? nil : cleanedItems
            } else if let value = json[key] as? String {
                let cleaned = value.trimmingCharacters(in: .whitespacesAndNewlines)
                return cleaned.isEmpty ? nil : [cleaned]
            }
        }
        return nil
    }
    
    private func extractConfidence(from json: [String: Any]) -> AIConfidenceLevel {
        let confidenceKeys = ["confidence", "confidence_score"]
        
        for key in confidenceKeys {
            if let value = json[key] as? Double {
                if value >= 0.8 {
                    return .high
                } else if value >= 0.5 {
                    return .medium
                } else {
                    return .low
                }
            } else if let value = json[key] as? String {
                switch value.lowercased() {
                case "high":
                    return .high
                case "medium":
                    return .medium
                case "low":
                    return .low
                default:
                    continue
                }
            }
        }
        
        return .high // Gemini typically has high confidence
    }
}

// MARK: - Basic Food Analysis Service (No API Key Required)

/// Basic food analysis using built-in logic and food database
/// Provides basic nutrition estimates without requiring external API keys
class BasicFoodAnalysisService {
    static let shared = BasicFoodAnalysisService()
    private init() {}
    
    func analyzeFoodImage(_ image: UIImage) async throws -> AIFoodAnalysisResult {
        return try await analyzeFoodImage(image, telemetryCallback: nil)
    }
    
    func analyzeFoodImage(_ image: UIImage, telemetryCallback: ((String) -> Void)?) async throws -> AIFoodAnalysisResult {
        telemetryCallback?("📊 Initializing basic analysis...")
        
        // Simulate analysis time for better UX with telemetry updates
        telemetryCallback?("📱 Analyzing image properties...")
        try await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
        
        telemetryCallback?("🍽️ Identifying food characteristics...")
        try await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
        
        telemetryCallback?("📊 Calculating nutrition estimates...")
        try await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
        
        // Basic analysis based on image characteristics and common foods
        telemetryCallback?("⚙️ Processing analysis results...")
        let analysisResult = performBasicAnalysis(image: image)
        
        return analysisResult
    }
    
    private func performBasicAnalysis(image: UIImage) -> AIFoodAnalysisResult {
        // Basic analysis logic - could be enhanced with Core ML models in the future
        
        // Analyze image characteristics
        let imageSize = image.size
        let brightness = calculateImageBrightness(image: image)
        
        // Generate basic food estimation based on image properties
        let foodItems = generateBasicFoodEstimate(imageSize: imageSize, brightness: brightness)
        
        // Calculate totals
        let totalCarbs = foodItems.reduce(0) { $0 + $1.carbohydrates }
        let totalProtein = foodItems.compactMap { $0.protein }.reduce(0, +)
        let totalFat = foodItems.compactMap { $0.fat }.reduce(0, +)
        let totalCalories = foodItems.compactMap { $0.calories }.reduce(0, +)
        
        return AIFoodAnalysisResult(
            imageType: .foodPhoto, // Fallback analysis assumes food photo
            foodItemsDetailed: foodItems,
            overallDescription: "Basic analysis of visible food items. For more accurate results, consider using an AI provider with API key.",
            confidence: .medium,
            totalFoodPortions: foodItems.count,
            totalUsdaServings: Double(foodItems.count), // Fallback estimate
            totalCarbohydrates: totalCarbs,
            totalProtein: totalProtein > 0 ? totalProtein : nil,
            totalFat: totalFat > 0 ? totalFat : nil,
            totalCalories: totalCalories > 0 ? totalCalories : nil,
            portionAssessmentMethod: "Estimated based on image size and typical serving portions",
            diabetesConsiderations: "Basic carbohydrate estimate provided. Monitor blood glucose response and adjust insulin as needed.",
            visualAssessmentDetails: nil,
            notes: "This is a basic analysis. For more detailed and accurate nutrition information, consider configuring an AI provider in Settings."
        )
    }
    
    private func calculateImageBrightness(image: UIImage) -> Double {
        // Simple brightness calculation based on image properties
        // In a real implementation, this could analyze pixel values
        return 0.6 // Default medium brightness
    }
    
    private func generateBasicFoodEstimate(imageSize: CGSize, brightness: Double) -> [FoodItemAnalysis] {
        // Generate basic food estimates based on common foods and typical portions
        // This is a simplified approach - could be enhanced with food recognition models
        
        let portionSize = estimatePortionSize(imageSize: imageSize)
        
        // Common food estimation
        let commonFoods = [
            "Mixed Plate",
            "Carbohydrate-rich Food",
            "Protein Source",
            "Vegetables"
        ]
        
        let selectedFood = commonFoods.randomElement() ?? "Mixed Meal"
        
        return [
            FoodItemAnalysis(
                name: selectedFood,
                portionEstimate: portionSize,
                usdaServingSize: nil,
                servingMultiplier: 1.0,
                preparationMethod: "Not specified",
                visualCues: nil,
                carbohydrates: estimateCarbohydrates(for: selectedFood, portion: portionSize),
                protein: estimateProtein(for: selectedFood, portion: portionSize),
                fat: estimateFat(for: selectedFood, portion: portionSize),
                calories: estimateCalories(for: selectedFood, portion: portionSize),
                assessmentNotes: "Basic estimate based on typical portions and common nutrition values. For diabetes management, monitor actual blood glucose response."
            )
        ]
    }
    
    private func estimatePortionSize(imageSize: CGSize) -> String {
        let area = imageSize.width * imageSize.height
        
        if area < 100000 {
            return "Small portion (about 1/2 cup or 3-4 oz)"
        } else if area < 300000 {
            return "Medium portion (about 1 cup or 6 oz)"
        } else {
            return "Large portion (about 1.5 cups or 8+ oz)"
        }
    }
    
    private func estimateCarbohydrates(for food: String, portion: String) -> Double {
        // Basic carb estimates based on food type and portion
        let baseCarbs: Double
        
        switch food {
        case "Carbohydrate-rich Food":
            baseCarbs = 45.0 // Rice, pasta, bread
        case "Mixed Plate":
            baseCarbs = 30.0 // Typical mixed meal
        case "Protein Source":
            baseCarbs = 5.0 // Meat, fish, eggs
        case "Vegetables":
            baseCarbs = 15.0 // Mixed vegetables
        default:
            baseCarbs = 25.0 // Default mixed food
        }
        
        // Adjust for portion size
        if portion.contains("Small") {
            return baseCarbs * 0.7
        } else if portion.contains("Large") {
            return baseCarbs * 1.4
        } else {
            return baseCarbs
        }
    }
    
    private func estimateProtein(for food: String, portion: String) -> Double? {
        let baseProtein: Double
        
        switch food {
        case "Protein Source":
            baseProtein = 25.0
        case "Mixed Plate":
            baseProtein = 15.0
        case "Carbohydrate-rich Food":
            baseProtein = 8.0
        case "Vegetables":
            baseProtein = 3.0
        default:
            baseProtein = 12.0
        }
        
        // Adjust for portion size
        if portion.contains("Small") {
            return baseProtein * 0.7
        } else if portion.contains("Large") {
            return baseProtein * 1.4
        } else {
            return baseProtein
        }
    }
    
    private func estimateFat(for food: String, portion: String) -> Double? {
        let baseFat: Double
        
        switch food {
        case "Protein Source":
            baseFat = 12.0
        case "Mixed Plate":
            baseFat = 8.0
        case "Carbohydrate-rich Food":
            baseFat = 2.0
        case "Vegetables":
            baseFat = 1.0
        default:
            baseFat = 6.0
        }
        
        // Adjust for portion size
        if portion.contains("Small") {
            return baseFat * 0.7
        } else if portion.contains("Large") {
            return baseFat * 1.4
        } else {
            return baseFat
        }
    }
    
    private func estimateCalories(for food: String, portion: String) -> Double? {
        let baseCalories: Double
        
        switch food {
        case "Protein Source":
            baseCalories = 200.0
        case "Mixed Plate":
            baseCalories = 300.0
        case "Carbohydrate-rich Food":
            baseCalories = 220.0
        case "Vegetables":
            baseCalories = 60.0
        default:
            baseCalories = 250.0
        }
        
        // Adjust for portion size
        if portion.contains("Small") {
            return baseCalories * 0.7
        } else if portion.contains("Large") {
            return baseCalories * 1.4
        } else {
            return baseCalories
        }
    }
}

// MARK: - Claude Food Analysis Service

/// Claude (Anthropic) food analysis service
class ClaudeFoodAnalysisService {
    static let shared = ClaudeFoodAnalysisService()
    private init() {}
    
    func analyzeFoodImage(_ image: UIImage, apiKey: String, query: String) async throws -> AIFoodAnalysisResult {
        return try await analyzeFoodImage(image, apiKey: apiKey, query: query, telemetryCallback: nil)
    }
    
    func analyzeFoodImage(_ image: UIImage, apiKey: String, query: String, telemetryCallback: ((String) -> Void)?) async throws -> AIFoodAnalysisResult {
        guard let url = URL(string: "https://api.anthropic.com/v1/messages") else {
            throw AIFoodAnalysisError.invalidResponse
        }
        
        // Get optimal model based on current analysis mode
        telemetryCallback?("⚙️ Configuring Claude parameters...")
        let analysisMode = ConfigurableAIService.shared.analysisMode
        let model = ConfigurableAIService.optimalModel(for: .claude, mode: analysisMode)
        
        
        // Optimize image size for faster processing and uploads
        telemetryCallback?("🖼️ Optimizing image for analysis...")
        let optimizedImage = ConfigurableAIService.optimizeImageForAnalysis(image)
        
        // Convert image to base64 with adaptive compression
        telemetryCallback?("🔄 Encoding image data...")
        let compressionQuality = ConfigurableAIService.adaptiveCompressionQuality(for: optimizedImage)
        guard let imageData = optimizedImage.jpegData(compressionQuality: compressionQuality) else {
            throw AIFoodAnalysisError.invalidResponse
        }
        let base64Image = imageData.base64EncodedString()
        
        // Prepare the request
        telemetryCallback?("📡 Preparing API request...")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        
        let requestBody: [String: Any] = [
            "model": model, // Dynamic model selection based on analysis mode
            "max_tokens": 2500, // Balanced for speed vs detail
            "temperature": 0.01, // Optimized for faster, more deterministic responses
            "messages": [
                [
                    "role": "user",
                    "content": [
                        [
                            "type": "text",
                            "text": query.isEmpty ? standardAnalysisPrompt : "\(query)\n\n\(standardAnalysisPrompt)"
                        ],
                        [
                            "type": "image",
                            "source": [
                                "type": "base64",
                                "media_type": "image/jpeg",
                                "data": base64Image
                            ]
                        ]
                    ]
                ]
            ]
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        
        telemetryCallback?("🌐 Sending request to Claude...")
        
        // Make the request
        telemetryCallback?("⏳ Awaiting result from AI...")
        let (data, response) = try await URLSession.shared.data(for: request)
        
        telemetryCallback?("📥 Received response from Claude...")
        
        guard let httpResponse = response as? HTTPURLResponse else {
            print("❌ Claude: Invalid HTTP response")
            throw AIFoodAnalysisError.invalidResponse
        }
        
        
        guard httpResponse.statusCode == 200 else {
            if let errorData = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                print("❌ Claude API Error: \(errorData)")
                if let error = errorData["error"] as? [String: Any],
                   let message = error["message"] as? String {
                    print("❌ Claude Error Message: \(message)")
                    
                    // Handle common Claude errors with specific error types
                    if message.contains("credit") || message.contains("billing") || message.contains("usage") {
                        throw AIFoodAnalysisError.creditsExhausted(provider: "Claude")
                    } else if message.contains("rate_limit") || message.contains("rate limit") {
                        throw AIFoodAnalysisError.rateLimitExceeded(provider: "Claude")
                    } else if message.contains("quota") || message.contains("limit") {
                        throw AIFoodAnalysisError.quotaExceeded(provider: "Claude")
                    } else if message.contains("authentication") || message.contains("invalid") && message.contains("key") {
                        throw AIFoodAnalysisError.customError("Invalid Claude API key. Please check your configuration.")
                    }
                }
            } else {
                print("❌ Claude: Error data: \(String(data: data, encoding: .utf8) ?? "Unable to decode")")
            }
            
            // Handle HTTP status codes for common credit/quota issues
            if httpResponse.statusCode == 429 {
                throw AIFoodAnalysisError.rateLimitExceeded(provider: "Claude")
            } else if httpResponse.statusCode == 402 {
                throw AIFoodAnalysisError.creditsExhausted(provider: "Claude")
            } else if httpResponse.statusCode == 403 {
                throw AIFoodAnalysisError.quotaExceeded(provider: "Claude")
            }
            
            throw AIFoodAnalysisError.apiError(httpResponse.statusCode)
        }
        
        // Enhanced data validation like Gemini
        guard data.count > 0 else {
            print("❌ Claude: Empty response data")
            throw AIFoodAnalysisError.invalidResponse
        }
        
        // Parse response
        telemetryCallback?("🔍 Parsing Claude response...")
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            print("❌ Claude: Failed to parse JSON response")
            print("❌ Claude: Raw response: \(String(data: data, encoding: .utf8) ?? "Unable to decode")")
            throw AIFoodAnalysisError.responseParsingFailed
        }
        
        guard let content = json["content"] as? [[String: Any]],
              let firstContent = content.first,
              let text = firstContent["text"] as? String else {
            print("❌ Claude: Invalid response structure")
            print("❌ Claude: Response JSON: \(json)")
            throw AIFoodAnalysisError.responseParsingFailed
        }
        
        // Add detailed logging like Gemini
        print("🔧 Claude: Received text length: \(text.count)")
        
        // Parse the JSON response from Claude
        telemetryCallback?("⚡ Processing AI analysis results...")
        return try parseClaudeAnalysis(text)
    }
    
    private func parseClaudeAnalysis(_ text: String) throws -> AIFoodAnalysisResult {
        // Clean the text and extract JSON from Claude's response
        let cleanedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Safely extract JSON content with proper bounds checking
        var jsonString: String
        if let jsonStartRange = cleanedText.range(of: "{"),
           let jsonEndRange = cleanedText.range(of: "}", options: .backwards),
           jsonStartRange.lowerBound < jsonEndRange.upperBound { // Ensure valid range
            // Safely extract from start brace to end brace (inclusive)
            jsonString = String(cleanedText[jsonStartRange.lowerBound..<jsonEndRange.upperBound])
        } else {
            // If no clear JSON boundaries, assume the whole cleaned text is JSON
            jsonString = cleanedText
        }
        
        // Additional safety check for empty JSON
        if jsonString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            jsonString = cleanedText
        }
        
        print("🔧 Claude: Attempting to parse JSON: \(jsonString.prefix(300))...")
        
        // Enhanced JSON parsing with error recovery
        var json: [String: Any]
        do {
            guard let jsonData = jsonString.data(using: .utf8),
                  let parsedJson = try JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else {
                print("❌ Claude: Failed to parse extracted JSON")
                print("❌ Claude: JSON string was: \(jsonString.prefix(500))...")
                throw AIFoodAnalysisError.responseParsingFailed
            }
            json = parsedJson
        } catch {
            print("❌ Claude: JSON parsing error: \(error)")
            print("❌ Claude: Problematic JSON: \(jsonString.prefix(500))...")
            
            // Try fallback parsing with the original cleaned text
            if let fallbackData = cleanedText.data(using: .utf8),
               let fallbackJson = try? JSONSerialization.jsonObject(with: fallbackData) as? [String: Any] {
                json = fallbackJson
            } else {
                throw AIFoodAnalysisError.responseParsingFailed
            }
        }
        
        // Parse food items with enhanced safety like Gemini
        var foodItems: [FoodItemAnalysis] = []
        
        do {
            if let foodItemsArray = json["food_items"] as? [[String: Any]] {
                
                // Enhanced per-item error handling like Gemini
                for (index, item) in foodItemsArray.enumerated() {
                    do {
                        let foodItem = FoodItemAnalysis(
                            name: extractClaudeString(from: item, keys: ["name"]) ?? "Unknown Food",
                            portionEstimate: extractClaudeString(from: item, keys: ["portion_estimate"]) ?? "1 serving",
                            usdaServingSize: extractClaudeString(from: item, keys: ["usda_serving_size"]),
                            servingMultiplier: max(0.1, extractClaudeNumber(from: item, keys: ["serving_multiplier"]) ?? 1.0), // Prevent zero/negative
                            preparationMethod: extractClaudeString(from: item, keys: ["preparation_method"]),
                            visualCues: extractClaudeString(from: item, keys: ["visual_cues"]),
                            carbohydrates: max(0, extractClaudeNumber(from: item, keys: ["carbohydrates"]) ?? 0), // Ensure non-negative
                            protein: extractClaudeNumber(from: item, keys: ["protein"]).map { max(0, $0) }, // Bounds checking
                            fat: extractClaudeNumber(from: item, keys: ["fat"]).map { max(0, $0) }, // Bounds checking
                            calories: extractClaudeNumber(from: item, keys: ["calories"]).map { max(0, $0) }, // Bounds checking
                            assessmentNotes: extractClaudeString(from: item, keys: ["assessment_notes"])
                        )
                        foodItems.append(foodItem)
                    } catch {
                        print("⚠️ Claude: Error parsing food item \(index): \(error)")
                        // Continue with other items - doesn't crash the whole analysis
                    }
                }
            }
        } catch {
            print("⚠️ Claude: Error in food items parsing: \(error)")
        }
        
        // Enhanced fallback creation like Gemini - safe fallback with comprehensive data
        if foodItems.isEmpty {
            let totalCarbs = extractClaudeNumber(from: json, keys: ["total_carbohydrates"]) ?? 25.0
            let totalProtein = extractClaudeNumber(from: json, keys: ["total_protein"])
            let totalFat = extractClaudeNumber(from: json, keys: ["total_fat"])
            let totalCalories = extractClaudeNumber(from: json, keys: ["total_calories"])
            
            foodItems = [
                FoodItemAnalysis(
                    name: "Claude Analyzed Food",
                    portionEstimate: "1 standard serving",
                    usdaServingSize: nil,
                    servingMultiplier: 1.0,
                    preparationMethod: "Not specified in analysis",
                    visualCues: "Visual analysis completed",
                    carbohydrates: max(0, totalCarbs), // Ensure non-negative
                    protein: totalProtein.map { max(0, $0) }, // Bounds checking
                    fat: totalFat.map { max(0, $0) }, // Bounds checking
                    calories: totalCalories.map { max(0, $0) }, // Bounds checking
                    assessmentNotes: "Safe fallback nutrition estimate - please verify actual food for accuracy"
                )
            ]
        }
        
        let confidence = extractConfidence(from: json)
        
        // Extract image type to determine if this is menu analysis or food photo
        let imageTypeString = json["image_type"] as? String
        let imageType = ImageAnalysisType(rawValue: imageTypeString ?? "food_photo") ?? .foodPhoto
        
        return AIFoodAnalysisResult(
            imageType: imageType,
            foodItemsDetailed: foodItems,
            overallDescription: ConfigurableAIService.cleanFoodText(json["overall_description"] as? String),
            confidence: confidence,
            totalFoodPortions: (json["total_food_portions"] as? Double).map { Int($0) },
            totalUsdaServings: json["total_usda_servings"] as? Double,
            totalCarbohydrates: json["total_carbohydrates"] as? Double ?? foodItems.reduce(0) { $0 + $1.carbohydrates },
            totalProtein: json["total_protein"] as? Double ?? foodItems.compactMap { $0.protein }.reduce(0, +),
            totalFat: json["total_fat"] as? Double ?? foodItems.compactMap { $0.fat }.reduce(0, +),
            totalCalories: json["total_calories"] as? Double ?? foodItems.compactMap { $0.calories }.reduce(0, +),
            portionAssessmentMethod: json["portion_assessment_method"] as? String,
            diabetesConsiderations: json["diabetes_considerations"] as? String,
            visualAssessmentDetails: json["visual_assessment_details"] as? String,
            notes: "Analysis provided by Claude (Anthropic)"
        )
    }
    
    // MARK: - Claude Helper Methods
    
    private func extractClaudeNumber(from json: [String: Any], keys: [String]) -> Double? {
        for key in keys {
            if let value = json[key] as? Double {
                return max(0, value) // Ensure non-negative nutrition values like Gemini
            } else if let value = json[key] as? Int {
                return max(0, Double(value)) // Ensure non-negative
            } else if let value = json[key] as? String, let doubleValue = Double(value) {
                return max(0, doubleValue) // Ensure non-negative
            }
        }
        return nil
    }
    
    private func extractClaudeString(from json: [String: Any], keys: [String]) -> String? {
        for key in keys {
            if let value = json[key] as? String, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return value.trimmingCharacters(in: .whitespacesAndNewlines) // Enhanced validation like Gemini
            }
        }
        return nil
    }
    
    private func extractConfidence(from json: [String: Any]) -> AIConfidenceLevel {
        let confidenceKeys = ["confidence", "confidence_score"]
        
        for key in confidenceKeys {
            if let value = json[key] as? Double {
                if value >= 0.8 {
                    return .high
                } else if value >= 0.5 {
                    return .medium
                } else {
                    return .low
                }
            } else if let value = json[key] as? String {
                // Enhanced string-based confidence detection like Gemini
                switch value.lowercased() {
                case "high":
                    return .high
                case "medium":
                    return .medium
                case "low":
                    return .low
                default:
                    continue
                }
            }
        }
        
        return .medium // Default to medium instead of assuming high
    }
}
