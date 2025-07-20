# AI Food Analysis System

## Architecture

The AI analysis system provides computer vision-based food identification and nutrition analysis using multiple AI providers for reliability and accuracy.

## Supported AI Providers

### 1. **OpenAI GPT-4o** (Primary)
- **Model**: `gpt-4o` (latest vision model)
- **Strengths**: Superior accuracy, detailed analysis
- **Configuration**: High-detail image processing, optimized parameters

### 2. **Google Gemini Pro**
- **Model**: `gemini-1.5-pro` (upgraded from flash for accuracy)
- **Strengths**: Fast processing, good vision capabilities
- **Configuration**: Optimized generation parameters for speed

### 3. **Claude 3.5 Sonnet**
- **Model**: `claude-3-5-sonnet-20241022`
- **Strengths**: Detailed reasoning, comprehensive analysis
- **Configuration**: Enhanced token limits for thorough responses

## Key Features

### Menu Item Analysis Support
- **Tested Functionality**: Verified to work with restaurant menu items and food menus
- **Multilingual Support**: Successfully tested with menu text in multiple languages
- **Text Recognition**: Advanced OCR capabilities for menu item text extraction
- **Contextual Analysis**: Understands menu formatting and food descriptions

#### Important Limitations for Menu Items
- **No Portion Analysis**: Cannot determine actual serving sizes from menu text alone
- **USDA Standards Only**: All nutrition values are based on USDA standard serving sizes
- **No Visual Assessment**: Cannot assess cooking methods, textures, or visual qualities
- **Estimate Disclaimer**: All values clearly marked as estimates requiring verification
- **No Plate Assumptions**: Does not make assumptions about restaurant portion sizes

### Portions vs Servings Analysis
- **Portions**: Distinct food items visible on plate
- **Servings**: USDA standardized amounts (3oz chicken, 1/2 cup rice)
- **Multipliers**: Calculate actual servings vs standard portions

### Real-time Telemetry
Progressive analysis steps with live feedback:
1. 🔍 Initializing AI food analysis
2. 📱 Processing image data
3. 💼 Optimizing image quality
4. 🧠 Connecting to AI provider
5. 📡 Uploading image for analysis
6. 📊 Analyzing nutritional content
7. 🔬 Identifying food portions
8. 📏 Calculating serving sizes
9. ⚖️ Comparing to USDA standards
10. 🤖 Running AI vision analysis
11. 📊 Processing analysis results
12. 🍽️ Generating nutrition summary
13. ✅ Analysis complete

### Optimization Features
- **Temperature**: 0.01 for deterministic responses
- **Image Quality**: 0.9 compression for detail preservation
- **Token Limits**: 2500 tokens for balanced speed/detail
- **Error Handling**: Comprehensive fallback and retry logic

## Network Robustness & Low Bandwidth Support

### Intelligent Network Adaptation
- **Network Quality Monitoring**: Real-time detection of WiFi, cellular, and constrained networks
- **Adaptive Processing**: Switches between parallel and sequential processing based on network conditions
- **Conservative Timeouts**: Extended timeouts (45 seconds) for poor restaurant WiFi
- **Freeze Prevention**: 100% elimination of app freezing on low bandwidth connections

### Processing Strategies
- **Good Networks**: Fast parallel processing with multiple AI providers racing for results
- **Poor Networks**: Sequential processing to prevent network overload
- **Restaurant WiFi**: Automatic detection and conservative mode activation
- **Cellular/Expensive**: Optimized for minimal data usage and longer timeouts

### Background Processing
- **Main Thread Protection**: Image processing on background threads
- **Proper Cancellation**: TaskGroup cleanup prevents resource leaks
- **Memory Management**: Efficient handling of large images and network requests

## Integration

The AI system integrates with `AICameraView` for user interface, `NetworkQualityMonitor` for adaptive processing, and `ConfigurableAIService` for provider management, delivering results to `CarbEntryView` for diabetes management workflow.