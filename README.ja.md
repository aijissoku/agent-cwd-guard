# agent-cwd-guard

[English](README.md) | 日本語

Windows で **Claude Code** と **Codex CLI** を、Web ページが確認なしでファイルを書き込めるフォルダでは使えないようにするガードです。

## なぜ必要か

ブラウザは、ユーザーの確認なしで次の場所にファイルを書き込めます。

| 場所 | 内容 |
|---|---|
| ダウンロードフォルダ | サイトが起動した最初のダウンロードは、確認なしで保存される |
| `%LOCALAPPDATA%\Google\Chrome*` | Cookie、IndexedDB、キャッシュ、OPFS など |

このようなフォルダで AI エージェントを起動すると、そこに置かれた `CLAUDE.md` / `AGENTS.md` / `.claude/settings.json`（解凍した zip に含まれていた場合など）がそのまま読み込まれ、プロンプトインジェクションやフックの実行につながる恐れがあります。

## 仕組み

二段構えです。

1. **システム全体のフック（本体）**：管理者しか書き換えられない設定に登録するので、ユーザー設定やプロジェクト設定では無効化できません。
   - Claude Code: `C:\Program Files\ClaudeCode\managed-settings.json`
   - Codex CLI: `C:\ProgramData\OpenAI\Codex\requirements.toml`
   - `SessionStart` / `UserPromptSubmit` / `PreToolUse` で `cwd_guard.py` を呼び出し、作業ディレクトリが対象なら拒否します。
2. **起動前チェック**：PowerShell 7 / 5.1 と Git Bash のプロファイルで `claude` / `codex` をラップし、プロジェクトのファイルが読まれる前に起動自体を止めます。

対象フォルダは実行のたびに計算します（ダウンロードフォルダの移動、Chrome プロファイルごとの保存先にも追従）。

## 必要なもの

- Windows 10 / 11
- PowerShell 7（`pwsh`）と管理者権限
- Python 3（標準ライブラリのみ使用）
- フック対応の Claude Code / Codex CLI（Claude Code 2.1.300、Codex CLI 0.162.1 で確認済み）

## 使い方

### 1. インストール

次の 3 通りから選んでください。

**A. 1 行で**（どの PowerShell ウィンドウからでも可）:

```powershell
irm https://raw.githubusercontent.com/aijissoku/agent-cwd-guard/main/get.ps1 | iex
```

最新版を `%LOCALAPPDATA%\agent-cwd-guard` にダウンロードし、`install.ps1` を管理者権限で実行します（UAC の確認が表示されます）。オプションを付ける場合:

```powershell
& ([scriptblock]::Create((irm https://raw.githubusercontent.com/aijissoku/agent-cwd-guard/main/get.ps1))) -NoProfiles
```

**B. AI エージェントに任せる**（Claude Code、Codex など）。ダウンロードフォルダ以外の通常のフォルダで起動し、次を貼り付けます。

```text
この Windows PC に agent-cwd-guard をインストールしてください: https://github.com/aijissoku/agent-cwd-guard
1. まず README.ja.md、install.ps1、cwd_guard.py を読み、この PC で何が変更されるかを数行で説明してください。
2. リポジトリをダウンロードフォルダ以外の通常のフォルダ（例: %USERPROFILE%\tools\agent-cwd-guard）に clone してください。
3. PowerShell 7 (pwsh) と Python 3 が入っているか確認し、なければ何を入れるべきか伝えて止まってください。
4. install.ps1 には管理者権限が必要です。このセッションが管理者でなければ、
   Start-Process pwsh -Verb RunAs -Wait -ArgumentList '-NoExit','-File','<clone 先>\install.ps1'
   を実行し、私が UAC を承認するのを待ってください。
5. test.ps1 -Live を実行して結果を報告してください。失敗した場合は出力を見せてください。管理設定ファイルを手で編集しないでください。
```

**C. 手動で**。**管理者として PowerShell 7 を開き**、次を実行します。

```powershell
git clone https://github.com/aijissoku/agent-cwd-guard.git
cd agent-cwd-guard
pwsh -File .\install.ps1
```

インストーラーが行うこと:

- `cwd_guard.py` を `C:\ProgramData\AgentGuard` にコピー
- Claude Code と Codex の管理設定にフックを追加（既存の設定は残す）
- 上記 3 フォルダを「管理者と SYSTEM のみ書き込み可」に設定
- PowerShell と Git Bash のプロファイルに起動前チェックを追加

何度実行しても同じ結果になります。

オプション:

| オプション | 効果 |
|---|---|
| `-Python <パス>` | 使用する `python.exe` を指定（省略時は自動検出） |
| `-NoProfiles` | シェルのプロファイルは変更せず、管理設定のフックだけを入れる |

### 2. 動作確認

**新しい**ターミナルを開いてから（プロファイルは起動時に読み込まれるため）:

```powershell
pwsh -File .\test.ps1        # パス判定とフック応答のテスト
pwsh -File .\test.ps1 -Live  # 実際にダウンロードフォルダで claude / codex を起動し、ブロックされることを確認
```

### 3. 普段の使い方

`claude` / `codex` はいつも通り使えます。対象フォルダでは起動を拒否します。

```
PS C:\Users\you\Downloads> claude
[AgentGuard] Claude CLI / Codex CLI cannot be used in this folder: C:\Users\you\Downloads
```

ダウンロードしたものを扱うときは、通常のプロジェクトフォルダに移動またはコピーしてから、そこでエージェントを起動してください。

### 4. 対象フォルダの変更

`cwd_guard.py` の `forbidden()` を編集し、`install.ps1` をもう一度実行します。表示メッセージは同じファイルの `MSG` です。

### 5. アンインストール

```powershell
pwsh -File .\uninstall.ps1
```

本ツールが追加したものだけを削除します。他のフックやプロファイルの内容はそのまま残ります。

## 制限事項

- 判定するのは**作業ディレクトリだけ**です。別のフォルダで起動したエージェントに、ダウンロードフォルダ内のファイルを読ませることはできます。防御の一層であり、完全なセキュリティ境界ではありません。
- `requirements.toml` に他から追加された `[hooks]` がある場合、Codex 部分は変更せず警告を出します。その場合は手動でマージしてください。
- VS Code 拡張や Codex デスクトップ版も同じ管理設定を読みますが、未検証です。

## ファイル構成

| ファイル | 役割 |
|---|---|
| `cwd_guard.py` | 判定とフック応答の本体 |
| `get.ps1` | ワンライン インストーラー（ダウンロード + 管理者でインストール） |
| `install.ps1` / `uninstall.ps1` | インストール / アンインストール |
| `common.ps1` | 共通のパスと関数 |
| `profile-snippets/` | プロファイルに挿入するラッパー |
| `test.ps1` | 動作確認 |

## ライセンス

[MIT](LICENSE)
