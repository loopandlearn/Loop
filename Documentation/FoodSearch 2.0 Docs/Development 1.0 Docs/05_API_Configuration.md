# API Configuration Guide

## AI Provider Setup

The Food Search system supports multiple AI providers for image analysis. Configuration is optional - the system works with OpenFoodFacts and USDA databases without API keys.

### OpenAI Configuration
**For GPT-4o Vision Analysis**

1. **Account Setup**:
   - Visit [platform.openai.com](https://platform.openai.com)
   - Create account and add billing method
   - Generate API key in API Keys section

2. **Configuration**:
   - Model: `gpt-4o` (automatically configured)
   - Rate Limits: Managed automatically
   - Cost: ~$0.01-0.03 per image analysis

3. **Recommended Settings**:
   - Usage Limits: Set monthly spending limit
   - Organization: Optional for team usage

### Google Gemini Configuration
**For Gemini Pro Vision Analysis**

1. **Account Setup**:
   - Visit [console.cloud.google.com](https://console.cloud.google.com)
   - Enable Gemini API in Google Cloud Console
   - Generate API key with Gemini API access

2. **Configuration**:
   - Model: `gemini-1.5-pro` (automatically configured)
   - Quota: Monitor in Google Cloud Console
   - Cost: Competitive rates with free tier

3. **Recommended Settings**:
   - Enable billing for production usage
   - Set up quota alerts

### Anthropic Claude Configuration
**For Claude Vision Analysis**

1. **Account Setup**:
   - Visit [console.anthropic.com](https://console.anthropic.com)
   - Create account and add payment method
   - Generate API key in Account Settings

2. **Configuration**:
   - Model: `claude-3-5-sonnet-20241022` (automatically configured)
   - Rate Limits: Managed by provider
   - Cost: Token-based pricing

3. **Recommended Settings**:
   - Set usage notifications
   - Monitor token consumption

## Service Configuration

### OpenFoodFacts (Free)
- **No API key required**
- **Rate Limits**: Respectful usage automatically managed
- **Coverage**: Global packaged food database
- **Data**: Nutrition facts, ingredients, allergens

### USDA FoodData Central (Free)
- **No API key required**
- **Rate Limits**: Government service, stable access
- **Coverage**: Comprehensive US food database
- **Data**: Detailed nutrition per 100g

## Provider Selection

### Automatic Fallback
- **Primary**: User-configured preferred provider
- **Secondary**: Automatic fallback to available providers
- **Fallback**: OpenFoodFacts/USDA for basic functionality

### Provider Comparison
| Provider | Accuracy | Speed | Cost | Setup |
|----------|----------|-------|------|-------|
| OpenAI GPT-4o | Excellent | Fast | Low | Easy |
| Google Gemini Pro | Very Good | Very Fast | Very Low | Easy |
| Claude 3.5 Sonnet | Excellent | Fast | Low | Easy |

## Error Handling

### Common Issues
- **Invalid API Key**: Clear error message with setup guidance
- **Rate Limits**: Automatic retry with user notification
- **Credit Exhaustion**: Provider switching recommendations
- **Network Issues**: Offline functionality with local databases

### User Guidance
- **Settings Access**: Direct links to configuration screens
- **Provider Status**: Real-time availability indicators
- **Troubleshooting**: Step-by-step resolution guides

## Security Considerations

### API Key Storage
- **Secure Storage**: Keys stored in iOS Keychain
- **Local Only**: No transmission to third parties
- **User Control**: Easy key management and deletion

### Data Privacy
- **Image Processing**: Sent only to selected AI provider
- **No Storage**: Images not retained by AI providers
- **User Choice**: Optional AI features, fallback available