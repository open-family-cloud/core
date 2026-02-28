# ストレージ戦略

## パターン別ストレージマッピング

| データ種別 | パターン1 (VPS) | パターン2 (k8s) | パターン3 (自宅+固定IP) | パターン4 (トンネル) |
|-----------|----------------|----------------|----------------------|-------------------|
| PostgreSQL | SSD (Volume) | PVC | SSD / NAS | NAS |
| Redis | SSD (Volume) | PVC | SSD / NAS | NAS |
| OpenLDAP | SSD (Volume) | PVC | SSD / NAS | NAS |
| Nextcloud ファイル | **S3** | **S3** | **NAS** / S3 | **NAS** |
| Synapse メディア | **S3** | **S3** | NAS / S3 | NAS |
| メール | Block Storage | PVC | **NAS** | **NAS** |
| Jellyfin メディア | S3 (rclone) | PVC | **NAS** | **NAS** |
| バックアップ | S3 (restic) | S3 (restic) | NAS + 任意S3 | NAS |

## S3 Object Storage（パターン1, 2）

Nextcloud の Primary Storage として S3 を使用:
- 容量制限なし（従量課金）
- サーバー障害時もデータ安全
- `config/nextcloud/custom.config.php` の `objectstore` で設定

## NAS ストレージ（パターン3, 4）

自宅の NAS にデータを集約:
- 大容量を低コストで確保
- ローカルアクセスが高速
- RAID / ZFS でデータ保護推奨

### 推奨マウント構成

```
/mnt/nas/
├── mail/          # docker-mailserver
│   ├── data/
│   ├── state/
│   └── logs/
├── media/         # Jellyfin メディア
├── backup/        # ローカルバックアップ
└── nextcloud/     # Nextcloud（S3 非使用時）
```

## バックアップ戦略

### 3-2-1 ルール

- **3**: データのコピーを3つ保持
- **2**: 異なる2種類のメディアに保存
- **1**: 1つはオフサイト（遠隔地）に保管

### パターン別の実装

| パターン | ローカル | リモート |
|---------|--------|--------|
| 1 (VPS) | - | S3 (restic) |
| 2 (k8s) | - | S3 (restic) |
| 3 (自宅) | NAS | S3 (任意) |
| 4 (トンネル) | NAS | S3 (任意) |
