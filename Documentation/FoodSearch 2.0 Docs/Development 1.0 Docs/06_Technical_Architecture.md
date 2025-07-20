# Technical Architecture

## System Design

### Architecture Pattern
- **Service-Oriented**: Modular services for different search types
- **Provider-Agnostic**: Pluggable AI and data providers
- **Event-Driven**: Reactive UI updates with real-time feedback
- **Fallback-First**: Graceful degradation with multiple data sources

### Core Components

#### 1. Service Layer
```swift
// AI Analysis Service
class ConfigurableAIService {
    func analyzeFoodImage(_ image: UIImage) async throws -> AIFoodAnalysisResult
}

// Barcode Service  
class BarcodeScannerService {
    func scanBarcode(_ image: UIImage) -> String?
}

// Voice Service
class VoiceSearchService {
    func startListening()
    func processVoiceQuery(_ text: String) async -> [OpenFoodFactsProduct]
}
```

#### 2. Data Models
```swift
// Unified Analysis Result
struct AIFoodAnalysisResult {
    let foodItemsDetailed: [FoodItemAnalysis]
    let totalFoodPortions: Int?
    let totalUsdaServings: Double?
    let totalCarbohydrates: Double
    // ... additional nutrition data
}

// Individual Food Analysis
struct FoodItemAnalysis {
    let name: String
    let portionEstimate: String
    let usdaServingSize: String?
    let servingMultiplier: Double
    let carbohydrates: Double
    // ... detailed nutrition breakdown
}
```

#### 3. Provider Management
```swift
enum SearchProvider: String, CaseIterable {
    case claude = "Anthropic (Claude API)"
    case googleGemini = "Google (Gemini API)"  
    case openAI = "OpenAI (ChatGPT API)"
    case openFoodFacts = "OpenFoodFacts (Default)"
    case usdaFoodData = "USDA FoodData Central"
}
```

## Data Flow Architecture

### 1. Input Processing
```
User Input → Input Validation → Service Selection → Provider Routing
```

### 2. AI Analysis Pipeline
```
Image Capture → Quality Optimization → Provider Selection → 
API Request → Response Processing → Result Validation → 
UI Integration
```

### 3. Error Handling Flow
```
Service Error → Error Classification → Fallback Provider → 
User Notification → Recovery Options
```

## Threading Model

### Main Thread Operations
- UI updates and user interactions
- Result display and navigation
- Error presentation

### Background Operations
- AI API requests
- Image processing
- Network communications
- Data parsing

### Thread Safety
```swift
// Example: Safe UI updates from background
await MainActor.run {
    self.isAnalyzing = false
    self.onFoodAnalyzed(result)
}
```

## Performance Optimizations

### 1. Image Processing
- **Compression**: 0.9 quality for detail preservation
- **Format**: JPEG for optimal AI processing
- **Size**: Optimized for API limits

### 2. AI Provider Optimization
- **Temperature**: 0.01 for deterministic responses
- **Token Limits**: 2500 for speed/detail balance
- **Concurrency**: Single request to prevent rate limiting

### 3. Caching Strategy
- **OpenFoodFacts**: Cached responses for repeated barcodes
- **USDA Data**: Local database for offline access
- **AI Results**: Session-based caching for re-analysis

## Error Recovery

### Provider Fallback
```swift
// Automatic provider switching
if primaryProvider.fails {
    try secondaryProvider.analyze(image)
} else if secondaryProvider.fails {
    fallback to localDatabase
}
```

### Network Resilience
- **Retry Logic**: Exponential backoff for transient failures
- **Offline Mode**: Local database fallback
- **Timeout Handling**: Graceful timeout with user options

## Security Architecture

### API Key Management
- **Storage**: iOS Keychain for secure persistence
- **Transmission**: HTTPS only for all communications
- **Validation**: Key format validation before usage

### Privacy Protection
- **Image Processing**: Temporary processing only
- **Data Retention**: No persistent storage of user images
- **Provider Isolation**: Each provider operates independently

## Monitoring and Telemetry

### Real-time Feedback
- **Progress Tracking**: 13-stage analysis pipeline
- **Status Updates**: Live telemetry window
- **Error Reporting**: Contextual error messages

### Performance Metrics
- **Response Times**: Per-provider performance tracking
- **Success Rates**: Provider reliability monitoring
- **User Engagement**: Feature usage analytics