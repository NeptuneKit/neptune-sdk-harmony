import {
  DemoGatewayDiscoveryCard,
  DemoLogCard,
  DemoSnapshot,
  DemoSourceCard,
  demoRuntime
} from '../runtime/DemoRuntime'
import router from '@ohos.router'

@Entry
@Component
struct Index {
  @State snapshot: DemoSnapshot = demoRuntime.snapshot()
  private autoDiscoveryTriggered: boolean = false

  aboutToAppear(): void {
    if (this.autoDiscoveryTriggered) {
      return
    }

    this.autoDiscoveryTriggered = true
    demoRuntime.setUIContext(this.getUIContext())
    demoRuntime.setGatewayDiscoveryContext(this.getUIContext().getHostContext() as Object)
    console.info('Index.aboutToAppear auto-triggering gateway discovery once.')
    this.snapshot = demoRuntime.beginGatewayDiscovery()
    void this.refreshGatewayDiscovery()
  }

  private runDemoBatch(): void {
    this.snapshot = demoRuntime.seedBatch()
    console.info(
      `Demo batch ${this.snapshot.batchIndex} written, queueSize=${this.snapshot.metrics.queueSize}, sources=${this.snapshot.sources.length}`
    )
  }

  private onDiscoverGatewayTap(): void {
    this.snapshot = demoRuntime.beginGatewayDiscovery()
    void this.refreshGatewayDiscovery()
  }

  private onRefreshSnapshotTap(): void {
    this.snapshot = demoRuntime.snapshot('已刷新快照')
  }

  private async refreshGatewayDiscovery(): Promise<void> {
    this.snapshot = await demoRuntime.discoverGateway()
  }

  private discoveryBadgeLabel(card: DemoGatewayDiscoveryCard): string {
    switch (card.state) {
      case 'loading':
        return 'discovering'
      case 'success':
        return 'success'
      case 'failed':
        return 'failed'
      default:
        return 'idle'
    }
  }

  private ingestBadgeLabel(card: DemoGatewayDiscoveryCard): string {
    switch (card.ingestState) {
      case 'loading':
        return 'ingesting'
      case 'success':
        return 'ingest ok'
      case 'failed':
        return 'ingest failed'
      default:
        return 'ingest idle'
    }
  }

  build() {
    Scroll() {
      Column({ space: 16 }) {
        Column({ space: 10 }) {
          Text('Neptune SDK Harmony Demo')
            .fontSize(30)
            .fontWeight(FontWeight.Bold)
            .fontColor('#F2F7FF')

          Text('点击下方按钮，把日志写入 HAR Runtime，并在页面内同步观察 metrics 与 sources 摘要。')
            .fontSize(14)
            .fontColor('#9FB2C7')
            .lineHeight(20)

          Row({ space: 10 }) {
            Text(this.snapshot.banner)
              .fontSize(13)
              .fontColor('#9FD6FF')
              .padding({ left: 12, right: 12, top: 8, bottom: 8 })
              .backgroundColor('rgba(36, 74, 106, 0.75)')
              .borderRadius(999)

            Text(`batch #${this.snapshot.batchIndex}`)
              .fontSize(13)
              .fontColor('#C7D4E6')
              .padding({ left: 12, right: 12, top: 8, bottom: 8 })
              .backgroundColor('rgba(255, 255, 255, 0.08)')
              .borderRadius(999)
          }
          .alignItems(VerticalAlign.Center)
        }
        .padding(20)
        .borderRadius(24)
        .backgroundColor('rgba(9, 18, 31, 0.92)')
        .border({
          width: 1,
          color: 'rgba(104, 143, 176, 0.25)'
        })

        Column({ space: 12 }) {
          Row({ space: 10 }) {
            Text('Gateway Discovery')
              .fontSize(18)
              .fontWeight(FontWeight.Bold)
              .fontColor('#F2F7FF')

            Text(this.discoveryBadgeLabel(this.snapshot.gatewayDiscovery))
              .fontSize(12)
              .fontColor('#04121C')
              .padding({ left: 12, right: 12, top: 6, bottom: 6 })
              .backgroundColor('#74D3F7')
              .borderRadius(999)
          }
          .alignItems(VerticalAlign.Center)

          Text('点击后先尝试 mDNS，再回退到手动 DSN 10.0.2.2:18765，并请求 /v2/gateway/discovery。发现成功后会自动 POST /v2/logs:ingest 一条日志。')
            .fontSize(13)
            .fontColor('#9FB2C7')
            .lineHeight(20)

          Button('发现并上报')
            .type(ButtonType.Capsule)
            .width('100%')
            .height(54)
            .fontSize(16)
            .fontWeight(FontWeight.Bold)
            .backgroundColor('#74D3F7')
            .fontColor('#04121C')
            .onClick(() => {
              void this.onDiscoverGatewayTap()
            })

          Column({ space: 4 }) {
            Text(this.snapshot.gatewayDiscovery.title)
              .fontSize(16)
              .fontWeight(FontWeight.Medium)
              .fontColor('#F2F7FF')
            Text(this.snapshot.gatewayDiscovery.detail)
              .fontSize(13)
              .fontColor('#A8BFD8')
              .lineHeight(19)
            Text(this.snapshot.gatewayDiscovery.timestamp)
              .fontSize(12)
              .fontColor('#74D3F7')
          }
          .padding(16)
          .borderRadius(18)
          .backgroundColor('rgba(15, 27, 42, 0.96)')

          Column({ space: 10 }) {
            Row({ space: 10 }) {
              Text('Ingest Result')
                .fontSize(16)
                .fontWeight(FontWeight.Medium)
                .fontColor('#F2F7FF')
              Text(this.ingestBadgeLabel(this.snapshot.gatewayDiscovery))
                .fontSize(12)
                .fontColor('#04121C')
                .padding({ left: 12, right: 12, top: 6, bottom: 6 })
                .backgroundColor('#F7C873')
                .borderRadius(999)
            }
            .alignItems(VerticalAlign.Center)

            Text(this.snapshot.gatewayDiscovery.ingestTitle)
              .fontSize(14)
              .fontWeight(FontWeight.Medium)
              .fontColor('#F2F7FF')
            Text(this.snapshot.gatewayDiscovery.ingestDetail)
              .fontSize(13)
              .fontColor('#A8BFD8')
              .lineHeight(19)
            Text(this.snapshot.gatewayDiscovery.ingestTimestamp)
              .fontSize(12)
              .fontColor('#F7C873')
          }
          .padding(16)
          .borderRadius(18)
          .backgroundColor('rgba(15, 27, 42, 0.96)')
        }
        .padding(20)
        .borderRadius(24)
        .backgroundColor('rgba(9, 18, 31, 0.92)')
        .border({
          width: 1,
          color: 'rgba(104, 143, 176, 0.25)'
        })

        Button('写入日志批次')
          .type(ButtonType.Capsule)
          .width('100%')
          .height(54)
          .fontSize(16)
          .fontWeight(FontWeight.Bold)
          .backgroundColor('#24C6DC')
          .fontColor('#04121C')
          .onClick(() => {
            this.runDemoBatch()
          })

        Button('刷新快照')
          .type(ButtonType.Capsule)
          .width('100%')
          .height(54)
          .fontSize(16)
          .fontWeight(FontWeight.Bold)
          .backgroundColor('#74D3F7')
          .fontColor('#04121C')
          .onClick(() => {
            this.onRefreshSnapshotTap()
          })

        Button('进入复杂二级页')
          .type(ButtonType.Capsule)
          .width('100%')
          .height(54)
          .fontSize(16)
          .fontWeight(FontWeight.Bold)
          .backgroundColor('#F7C873')
          .fontColor('#04121C')
          .onClick(() => {
            router.pushUrl({ url: 'pages/DeepDive' })
          })

        Column({ space: 12 }) {
          Text('Metrics')
            .fontSize(18)
            .fontWeight(FontWeight.Bold)
            .fontColor('#F2F7FF')

          Row({ space: 12 }) {
            Column({ space: 6 }) {
              Text(String(this.snapshot.metrics.queueSize))
                .fontSize(28)
                .fontWeight(FontWeight.Bold)
                .fontColor('#F2F7FF')
              Text('queueSize')
                .fontSize(12)
                .fontColor('#9FB2C7')
            }
            .layoutWeight(1)
            .padding(16)
            .borderRadius(18)
            .backgroundColor('rgba(15, 27, 42, 0.96)')

            Column({ space: 6 }) {
              Text(String(this.snapshot.metrics.totalIngested))
                .fontSize(28)
                .fontWeight(FontWeight.Bold)
                .fontColor('#F2F7FF')
              Text('totalIngested')
                .fontSize(12)
                .fontColor('#9FB2C7')
            }
            .layoutWeight(1)
            .padding(16)
            .borderRadius(18)
            .backgroundColor('rgba(15, 27, 42, 0.96)')
          }

          Row({ space: 12 }) {
            Column({ space: 6 }) {
              Text(String(this.snapshot.metrics.droppedOverflow))
                .fontSize(24)
                .fontWeight(FontWeight.Bold)
                .fontColor('#F2F7FF')
              Text('droppedOverflow')
                .fontSize(12)
                .fontColor('#9FB2C7')
            }
            .layoutWeight(1)
            .padding(16)
            .borderRadius(18)
            .backgroundColor('rgba(15, 27, 42, 0.96)')

            Column({ space: 6 }) {
              Text(String(this.snapshot.metrics.totalExported))
                .fontSize(24)
                .fontWeight(FontWeight.Bold)
                .fontColor('#F2F7FF')
              Text('totalExported')
                .fontSize(12)
                .fontColor('#9FB2C7')
            }
            .layoutWeight(1)
            .padding(16)
            .borderRadius(18)
            .backgroundColor('rgba(15, 27, 42, 0.96)')
          }
        }
        .padding(20)
        .borderRadius(24)
        .backgroundColor('rgba(9, 18, 31, 0.92)')
        .border({
          width: 1,
          color: 'rgba(104, 143, 176, 0.25)'
        })

        Column({ space: 12 }) {
          Text(`Sources · ${this.snapshot.sources.length}`)
            .fontSize(18)
            .fontWeight(FontWeight.Bold)
            .fontColor('#F2F7FF')

          if (this.snapshot.sources.length === 0) {
            Text('还没有来源快照，点击上方按钮后会显示 Harmony 模拟器来源。')
              .fontSize(13)
              .fontColor('#9FB2C7')
              .lineHeight(20)
          } else {
            Column({ space: 10 }) {
              ForEach(this.snapshot.sources, (source: DemoSourceCard) => {
                Column({ space: 6 }) {
                  Text(source.title)
                    .fontSize(15)
                    .fontWeight(FontWeight.Medium)
                    .fontColor('#F2F7FF')
                  Text(source.detail)
                    .fontSize(12)
                    .fontColor('#A8BFD8')
                    .lineHeight(18)
                  Text(source.timestamp)
                    .fontSize(12)
                    .fontColor('#74D3F7')
                }
                .padding(14)
                .borderRadius(16)
                .backgroundColor('rgba(15, 27, 42, 0.96)')
              }, (source: DemoSourceCard) => source.id)
            }
          }
        }
        .padding(20)
        .borderRadius(24)
        .backgroundColor('rgba(9, 18, 31, 0.92)')
        .border({
          width: 1,
          color: 'rgba(104, 143, 176, 0.25)'
        })

        Column({ space: 12 }) {
          Text('Recent logs')
            .fontSize(18)
            .fontWeight(FontWeight.Bold)
            .fontColor('#F2F7FF')

          if (this.snapshot.recentLogs.length === 0) {
            Text('当前队列为空。点击按钮后，这里会显示最近写入的日志。')
              .fontSize(13)
              .fontColor('#9FB2C7')
              .lineHeight(20)
          } else {
            Column({ space: 10 }) {
              ForEach(this.snapshot.recentLogs, (log: DemoLogCard) => {
                Column({ space: 4 }) {
                  Text(log.title)
                    .fontSize(14)
                    .fontWeight(FontWeight.Medium)
                    .fontColor('#F2F7FF')
                  Text(log.detail)
                    .fontSize(12)
                    .fontColor('#A8BFD8')
                    .lineHeight(18)
                  Text(log.timestamp)
                    .fontSize(12)
                    .fontColor('#F6C06B')
                }
                .padding(14)
                .borderRadius(16)
                .backgroundColor('rgba(15, 27, 42, 0.96)')
              }, (log: DemoLogCard) => log.id)
            }
          }
        }
        .padding(20)
        .borderRadius(24)
        .backgroundColor('rgba(9, 18, 31, 0.92)')
        .border({
          width: 1,
          color: 'rgba(104, 143, 176, 0.25)'
        })
      }
      .padding({ left: 20, right: 20, top: 24, bottom: 28 })
      .width('100%')
    }
    .scrollBar(BarState.Auto)
    .backgroundColor('#06101A')
    .width('100%')
    .height('100%')
  }
}
