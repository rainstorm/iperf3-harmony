# 发布构建与签名

> 本文件说明如何用**你自己的**发布证书把本工程打成可分发的 `.app` 包。
> 文中不包含任何密钥；请把你的签名材料放在本机不入库的目录（例如 `signing/release/`，已被 `.gitignore` 忽略）。

## 前置材料（在 AppGallery Connect 申请）

1. 生成私钥与证书请求文件（本机执行，私钥不出本机）：

   ```bash
   keytool -genkeypair -alias myalias -keyalg EC -groupname secp256r1 \
       -sigalg SHA256withECDSA -dname "C=CN,O=<org>,OU=<unit>,CN=<name>" \
       -keystore my-release.p12 -storetype pkcs12 -validity 9125 \
       -storepass '<your-password>' -keypass '<your-password>'

   # CSR 必须使用 SHA256withECDSA 签名，否则 AGC 会报「CSR 文件无效」
   keytool -certreq -alias myalias -keystore my-release.p12 -storetype pkcs12 \
       -file my-release.csr -storepass '<your-password>' -sigalg SHA256withECDSA
   ```

2. AGC → 项目设置 → 证书、App ID 和 Profile：
   - **证书管理 → 新增证书**：类型「发布证书」，上传 `my-release.csr`，下载 `.cer`
   - **Profile 管理 → 添加 Profile**：类型「发布」，绑定应用与上述证书，下载 `.p7b`

把 `my-release.p12` / `.cer` / `.p7b` 放到本机签名目录（**不要提交到仓库**）。

## 打包与签名

hvigor 的内置签名要求密码以 DevEco 自有加密格式（`material/` 目录 + 密文）存放，命令行不便复现，
因此这里用 SDK 自带的 `hap-sign-tool` 分两步签名：**先签 HAP，再签 APP**。

```bash
DEVECO="<DevEco 安装目录>"            # 例如 E:/Huawei/DevEcoStudio
SIGN="<你的签名目录绝对路径>"           # 含 my-release.p12 / .cer / .p7b
JAVA="$DEVECO/jbr/bin/java.exe"
TOOL="$DEVECO/sdk/default/openharmony/toolchains/lib/hap-sign-tool.jar"
PRJ="<本仓库绝对路径>"

# 1) release 模式构建未签名包
export JAVA_HOME="$DEVECO/jbr"
export DEVECO_SDK_HOME="$DEVECO/sdk"
cd "$PRJ"
"$DEVECO/tools/node/node.exe" "$DEVECO/tools/hvigor/bin/hvigorw.js" \
    assembleApp --mode project -p product=default -p buildMode=release \
    -p enableSignTask=false --no-daemon

# 2) 给 HAP 签名（-compatibleVersion 填 compatibleSdkVersion 的主版本号）
"$JAVA" -jar "$TOOL" sign-app -mode localSign \
    -keyAlias myalias -keyPwd '<your-password>' \
    -appCertFile "$SIGN/my-release.cer" -profileFile "$SIGN/my-release.p7b" \
    -signAlg SHA256withECDSA \
    -keystoreFile "$SIGN/my-release.p12" -keystorePwd '<your-password>' \
    -inFile  "$PRJ/entry/build/default/outputs/default/entry-default-unsigned.hap" \
    -outFile "$PRJ/build/outputs/default/entry-default-release-signed.hap" \
    -compatibleVersion 12

# 3) 用签名后的 HAP 替换 .app 内的未签名 HAP（保持 zip 条目结构）
python - "$PRJ/build/outputs/default/iperf3-harmony-default-unsigned.app" \
          "$PRJ/build/outputs/default/entry-default-release-signed.hap" \
          "$PRJ/build/outputs/default/iperf3-harmony-default-repacked.app" <<'PY'
import sys, zipfile
src, hap, dst = sys.argv[1], sys.argv[2], sys.argv[3]
hap_bytes = open(hap, 'rb').read()
zin = zipfile.ZipFile(src)
with zipfile.ZipFile(dst, 'w', zipfile.ZIP_DEFLATED) as zout:
    for item in zin.infolist():
        zout.writestr(item, hap_bytes if item.filename.endswith('.hap') else zin.read(item.filename))
PY

# 4) 给 .app 签名
"$JAVA" -jar "$TOOL" sign-app -mode localSign \
    -keyAlias myalias -keyPwd '<your-password>' \
    -appCertFile "$SIGN/my-release.cer" -profileFile "$SIGN/my-release.p7b" \
    -signAlg SHA256withECDSA \
    -keystoreFile "$SIGN/my-release.p12" -keystorePwd '<your-password>' \
    -inFile  "$PRJ/build/outputs/default/iperf3-harmony-default-repacked.app" \
    -outFile "$PRJ/build/outputs/default/iperf3-harmony-default-release-signed.app"

# 5) 校验（两步都应输出 Verify success）
"$JAVA" -jar "$TOOL" verify-app -inFile "$PRJ/build/outputs/default/entry-default-release-signed.hap" \
    -outCertChain /tmp/cc.cer -outProfile /tmp/pp.p7b
"$JAVA" -jar "$TOOL" verify-app -inFile "$PRJ/build/outputs/default/iperf3-harmony-default-release-signed.app" \
    -outCertChain /tmp/cc2.cer -outProfile /tmp/pp2.p7b
```

## 常见问题

| 现象 | 原因与处理 |
| --- | --- |
| AGC 提示「CSR 文件无效」 | CSR 用了 SHA384withECDSA（keytool 默认）——用 `-sigalg SHA256withECDSA` 重新生成 CSR；密钥对不变，`.p12` 仍有效 |
| 只签了 `.app`，AGC 报包校验失败 | 包内 HAP 也必须签名；`enableSignTask=false` 会跳过 HAP 签名，需按上面第 2、3 步处理 |
| `hdc install` 报 `not trusted app source` | 发布签名包不能侧载，只能通过应用商店分发；自用请改用调试签名 |
| 想查签名信息 | `java -jar hap-sign-tool.jar verify-app -inFile <包> -outCertChain <cer> -outProfile <p7b>` |
