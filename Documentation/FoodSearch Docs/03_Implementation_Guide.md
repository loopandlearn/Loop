# Food Search Implementation Guide

## File Structure

### Core Services
```
/Services/
├── AIFoodAnalysis.swift          # AI provider implementations and analysis logic
├── BarcodeScannerService.swift   # Barcode detection and OpenFoodFacts integration
├── VoiceSearchService.swift      # Speech recognition and voice processing
├── OpenFoodFactsService.swift    # OpenFoodFacts API integration
└── USDAFoodDataService.swift     # USDA FoodData Central integration
```

### User Interface
```
/Views/
├── AICameraView.swift            # AI image analysis interface with telemetry
├── BarcodeScannerView.swift      # Barcode scanning interface
├── VoiceSearchView.swift         # Voice input interface
├── FoodSearchBar.swift           # Unified search interface component
└── CarbEntryView.swift           # Enhanced with food search integration
```

### View Models
```
/View Models/
└── CarbEntryViewModel.swift      # Enhanced with AI analysis and food search
```

## Key Implementation Details

### 1. **AI Analysis Integration**
- **Entry Point**: `AICameraView` auto-launches camera and processes results
- **Processing**: Multi-stage analysis with real-time telemetry feedback
- **Results**: Structured `AIFoodAnalysisResult` with detailed nutrition data
- **Integration**: Results converted to `OpenFoodFactsProduct` format for compatibility

### 2. **Search Provider Management**
- **Enum-based**: `SearchProvider` enum defines available services
- **Type-specific**: Different providers for different search types
- **Fallback Logic**: Multiple providers with automatic failover
- **Configuration**: User-configurable API keys and provider preferences

### 3. **Data Flow**
```
User Input → Search Service → Data Processing → Result Conversion → CarbEntry Integration
```

### 4. **Error Handling**
- **Network Failures**: Automatic retry with exponential backoff
- **API Errors**: Provider-specific error messages and fallback options
- **Rate Limits**: Intelligent handling with user guidance
- **Credit Exhaustion**: Clear messaging with provider switching options

## Configuration Requirements

### API Keys (Optional)
- **OpenAI**: For GPT-4o vision analysis
- **Google**: For Gemini Pro vision analysis  
- **Anthropic**: For Claude vision analysis

### Permissions
- **Camera**: Required for barcode scanning and AI image analysis
- **Microphone**: Required for voice search functionality
- **Network**: Required for all external API communications

## Integration Points

### CarbEntryView Enhancement
- Added AI camera button in search bar
- Enhanced with AI analysis result display
- Integrated telemetry and progress feedback
- Maintains existing carb entry workflow

### Data Compatibility
- All search results convert to `OpenFoodFactsProduct` format
- Maintains compatibility with existing Loop nutrition tracking
- Preserves serving size and nutrition calculation logic