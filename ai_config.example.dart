// Gemini settings for the app's AI features. This file is not committed
// (see .gitignore); copy this file to lib/ai_config.dart and add your key.
const geminiApiKey = 'PASTE-YOUR-GEMINI-API-KEY';

/// Tried in order; the next model is used when one is overloaded or unavailable.
const geminiModels = ['gemini-3.6-flash', 'gemini-flash-latest', 'gemini-flash-lite-latest'];

/// Backup AI, used when Gemini is too slow or unavailable.
const groqApiKey = 'PASTE_YOUR_GROQ_KEY';
const groqModel = 'qwen/qwen3.8-27b';
