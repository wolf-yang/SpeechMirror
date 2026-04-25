# 语镜（SpeechMirror）

语镜是一个**本地优先**的智能社交话术助手：你可以配置自己的模型接口（OpenAI 兼容），在首页或 Android 悬浮窗里做改写、粘贴、发送辅助，并通过模式库与人格蒸馏持续沉淀表达风格。

## 核心功能

- 首页改写：支持模式选择、场景包、长度/渠道控制。
- 输出模式：
  - 单条结果（流式展示）
  - 三条结果（非流式一次性返回）
- 模式库：内置模式 + 自定义模式 + 人物模式。
- 蒸馏工坊：从文本片段蒸馏人格风格并生成人物模式。
- 历史记录：保存原文与改写结果，便于复用。
- Android 悬浮球：
  - 顶部浮窗快捷改写
  - 结果复制/填充
  - 与无障碍服务协同做输入框粘贴与发送按钮点击辅助

## 技术架构概览

- Flutter：主应用 UI 与业务逻辑。
- Android 原生：
  - `OverlayService`：悬浮球/顶部浮窗/结果卡交互
  - `SpeechMirrorAccessibilityService`：键盘检测、上下文采集、粘贴与发送辅助
- 双引擎方案：
  - 主引擎：`lib/main.dart`
  - 悬浮窗次引擎：`lib/overlay_main.dart`
- 通信：
  - `com.speechmirror.app/overlay`（主通道）
  - `com.speechmirror.app/overlay_panel`（面板通道）

## 项目结构（关键目录）

- `lib/features/`：页面与交互（home/modes/distill/profile/history/shell）
- `lib/core/`：LLM、Prompt、场景包等核心能力
- `lib/data/`：SQLite、KV、凭据、Repository 与数据模型
- `lib/platform/`：Flutter 与 Android MethodChannel 桥接
- `android/app/src/main/kotlin/com/speechmirror/app/`：原生服务与权限逻辑
- `assets/prompts/`、`assets/android/`、`assets/tools/`：提示词、发送按钮映射、工具资源

## 运行环境要求

- Flutter: `>=3.22.0`
- Dart SDK: `>=3.4.0 <4.0.0`
- Android:
  - `minSdk 24`
  - `targetSdk 36`
  - `compileSdk 36`
- JVM / Gradle：建议 **Java 17**（至少 Java 11；低版本会构建失败）

## 快速开始（开发）

```bash
flutter pub get
flutter run
```

常用检查：

```bash
flutter analyze
```

Android 打包（在 `android/` 目录）：

```bash
./gradlew :app:assembleDebug
```

## 首次使用（产品）

1. 打开“我的” -> “API 与模型”，配置：
   - Base URL（OpenAI 兼容）
   - Model
   - API Key
2. 回到首页选择语言模式，输入文本后转换。
3. 如需悬浮能力：在“我的”中打开“启用悬浮球（Android）”。
4. 如需上下文采集：打开“允许浮窗采集对话”，并开启系统无障碍服务。

## Android 权限与系统设置

应用会用到以下权限/能力（见 `AndroidManifest.xml`）：

- 悬浮窗：`SYSTEM_ALERT_WINDOW`
- 通知（Android 13+）：`POST_NOTIFICATIONS`
- 前台服务：`FOREGROUND_SERVICE`、`FOREGROUND_SERVICE_DATA_SYNC`
- 无障碍服务绑定：`BIND_ACCESSIBILITY_SERVICE`（服务声明）

若在系统里找不到悬浮权限入口，可通过应用内“悬浮窗权限帮助”跳转到：

- 应用详情页
- “显示在其他应用上层”设置页

## 数据与隐私

- 本地存储：
  - SQLite（模式、历史、通用 KV）
  - Secure Storage（Base URL / Model / API Key）
- 语镜不提供自有模型后端。
- 仅在你主动触发改写/蒸馏等调用时，把必要文本发送到你配置的模型接口。
- 支持“一键清空数据”（历史、非内置模式、本地设置与已保存凭据）。

## 关键配置项（app_kv）

- `overlay_auto_show`：悬浮球自动显示
- `collect_dialog_enabled`：允许采集当前界面文本
- `rewrite_output_count`：输出条数（`1` 或 `3`）
- `recent_mode_ids`：最近模式列表
- `selected_mode_id`：当前选中模式（首页与浮窗模式同步）

## 主要能力入口（代码）

- 首页改写：`lib/features/home/home_screen.dart`
- 悬浮窗改写主面板：`lib/overlay/overlay_panel_screen.dart`
- 悬浮窗次引擎入口：`lib/overlay_main.dart`
- LLM 客户端：`lib/core/llm/llm_client.dart`
- Prompt 构建：`lib/core/prompt/prompt_builder.dart`
- 原生浮窗服务：`android/app/src/main/kotlin/com/speechmirror/app/OverlayService.kt`
- 无障碍服务：`android/app/src/main/kotlin/com/speechmirror/app/SpeechMirrorAccessibilityService.kt`

## 已知限制与兼容性说明

- 第三方 App 的输入框和“发送按钮”适配存在机型/版本差异。
- 无障碍能力依赖系统授权状态，未授权时相关功能会降级或失败。
- 悬浮窗与通知权限在不同 ROM 上可能表现不一致。
- 首次拉起次引擎时，设备性能较弱场景可能出现加载延迟。

## License

当前仓库未单独声明 License 文件；如需开源发布，请补充许可证。
