# secure-private-access-with-single-public-nlb

<a href="https://dev.classmethod.jp/articles/securing-private-access-route-with-single-public-nlb/" rel="noopener" target="_blank">外部公開している NLB 1 台だけでプライベートなアクセス経路も確保する | DevelopersIO</a> ブログのリポジトリです。

## 前提条件
- AWSアカウントを持っていること
- Terraformの実行環境があること
- Sysdig Secureのアカウントを持っていること

## リソース

下記リソースをデプロイします。
- VPC
  - main用VPC
  - PrivateLink用VPC
  - プライベートアクセス用VPC
- Subnet(Public/Private)
- Route Table
- Internet Gateway
- Nat Gateway
- EC2
  - webサーバー
  - プライベートアクセス用サーバー
- EC2 Instance Connect Endpoint
- Network Load Balancer
- エンドポイントサービス
- インターフェイス型VPCエンドポイント
- VPCピアリング

## 構成図

<img src="/image/khiraki_privatelink_public_privatelink_demo.png">

## セットアップ手順

### クローン
```bash
git clone https://github.com/Keisuke-Hiraki/secure-private-access-with-single-public-nlb.git
```

### 初期化
```bash
terraform init
```

### 作成

-varオプションに引数を渡す場合のコマンドは下記です。
```bash
terraform apply
```
### 削除

```bash
terraform destroy
```
