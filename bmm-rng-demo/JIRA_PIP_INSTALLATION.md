# Jira OPS 工作記錄 - pip 安裝

**Summary**: BMM RNG Demo EC2 - Install pip for Python Package Management

**Issue Type**: Task

**Labels**: `bmm-rng`, `python`, `pip`, `infrastructure`

---

## 目的
在 BMM RNG Demo EC2 instance 上安裝 pip，以便進行 Python 套件管理和應用程式部署。

## 背景
- **EC2 Instance**: rng-game-srv01
- **OS**: Amazon Linux 2023
- **Python 版本**: 3.9.24 (已安裝)
- **問題**: 系統缺少 pip/pip3 工具

## 執行步驟

### 1. 問題診斷
檢查 Python 和 pip 狀態：
```bash
# Python 已安裝
python3 --version
# Output: Python 3.9.24

# pip 未安裝
pip3 --version
# Output: command not found
```

### 2. 安裝 pip
使用 DNF 套件管理器安裝：
```bash
sudo dnf install -y python3-pip
```

**安裝內容**:
- `python3-pip-21.3.1-2.amzn2023.0.14.noarch`
- `libxcrypt-compat-4.4.33-7.amzn2023.x86_64` (依賴套件)

### 3. 驗證安裝
```bash
# 驗證 pip3
pip3 --version
# Output: pip 21.3.1 from /usr/lib/python3.9/site-packages/pip (python 3.9)

# 驗證 pip alias
pip --version
# Output: pip 21.3.1 from /usr/lib/python3.9/site-packages/pip (python 3.9)
```

## 結果

✅ **pip 已成功安裝並可正常使用**
✅ **兩種命令都可用**: `pip` 和 `pip3`
✅ **Python 套件管理功能已就緒**

## 系統資訊

| 項目 | 版本/資訊 |
|------|----------|
| OS | Amazon Linux 2023 |
| Python | 3.9.24 |
| pip | 21.3.1 |
| 安裝方式 | DNF package manager |

## 使用說明

### 基本命令
```bash
# 安裝套件
pip install <package-name>
pip3 install <package-name>

# 升級 pip
pip3 install --upgrade pip

# 列出已安裝套件
pip list

# 安裝 requirements.txt
pip install -r requirements.txt
```

### 虛擬環境（建議）
```bash
# 方式 1: 使用 venv (Python 內建)
python3 -m venv venv
source venv/bin/activate

# 方式 2: 使用 virtualenv
pip install virtualenv
virtualenv venv
source venv/bin/activate
```

## 注意事項

1. **虛擬環境使用**
   - 建議在專案中使用虛擬環境隔離依賴
   - 避免污染系統 Python 環境

2. **權限管理**
   - 系統級安裝需要 `sudo`
   - 虛擬環境內安裝不需要 `sudo`

3. **套件安全性**
   - 安裝前檢查套件來源
   - 定期更新套件以修復安全漏洞

## 後續建議

1. **升級 pip 到最新版本**
   ```bash
   pip3 install --upgrade pip
   ```

2. **安裝常用開發工具**
   ```bash
   pip install virtualenv ipython pytest
   ```

3. **配置 pip 鏡像**（可選，加速下載）
   ```bash
   # 編輯 ~/.pip/pip.conf
   [global]
   index-url = https://pypi.tuna.tsinghua.edu.cn/simple
   ```

## 相關資源

- **EC2 Instance**: rng-game-srv01
- **Region**: ap-east-1
- **Project**: BMM RNG Demo
- **Documentation**: Official pip docs - https://pip.pypa.io/

---

**建立日期**: 2025-12-01
**執行人員**: DevOps Team
**狀態**: ✅ 完成
**預估時間**: 5 分鐘
**實際時間**: 3 分鐘
