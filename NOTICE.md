# 版权与来源声明

## 原始作品

本仓库的所有基础代码来自：

- **项目**：`lovetrack`
- **地址**：https://github.com/2000lla/lovetrack
- **作者**：2000lla（及其贡献者）

原始项目中包含的以下内容均为原作者成果：

- iOS 客户端全部业务代码：`App/`、`Location/`、`Log/`、`Map/`、`Models/`、`Network/`、`Relationship/`、`UI/` 目录下未经本仓库修改的文件
- 产品文档、UI 原型、PRD、架构文档（原仓库 `01-research/`、`02-ui-prototype/`、`03-architecture/*.md`、`04-prd/`）
- 后端实现（原仓库 `05-backend/`）

## 授权状况

**原始项目没有包含任何 LICENSE / COPYING / NOTICE 文件，也未在 README 中声明开源许可证。**

根据默认版权规则（伯尔尼公约及各国著作权法），未声明许可证的公开代码视为 **「保留所有权利（All Rights Reserved）」**——公开可见不等于授权使用、修改或分发。

因此：

- 本仓库**不声称**对原始代码拥有任何权利
- 本仓库的修改部分由 AI 助手完成，同样**不构成对原始作品的再许可**
- 本仓库仅作 **个人学习与自用**，**不做商业分发、不售卖、不提供付费服务**
- **不建议**将本仓库内容用于任何需要明确授权的场景

## 如果原作者有异议

原始作者如认为本仓库的存在不妥，请通过以下任一方式联系：

- 在本仓库开 Issue
- 通过 GitHub 联系仓库所有者 `Anryyanrui-ship-it`

收到通知后会**立即删除本仓库**，无需进一步说明。

## 本仓库的修改部分

相对原始项目的全部改动（详见 `CHANGELOG.md`）由 AI 助手在用户明确需求下完成：

- 构建配置修复（`project.pbxproj`、`Secrets.xcconfig`、`BackendConfig.swift`）
- 配对流程加固（`App/PairScreen.swift`、`App/LoveTrackApp.swift`）
- CI 工作流（`.github/workflows/build-ios.yml`）
- 辅助脚本（`tools/`）
- 文档（`README.md`、`CHANGELOG.md`、`NOTICE.md`、`README-上传与安装.md`）

## 免责

本项目按「现状」提供，不附带任何明示或暗示的担保。使用者自行承担因使用本代码产生的一切后果，包括但不限于数据丢失、设备异常、位置隐私泄露。

位置数据涉及个人隐私，请仅在双方知情同意的前提下使用。
