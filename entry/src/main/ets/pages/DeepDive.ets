import { demoRuntime } from '../runtime/DemoRuntime'

@Component
struct MetricChip {
  @Prop title: string
  @Prop value: string
  @Prop tint: string

  build() {
    Column({ space: 6 }) {
      Text(this.value)
        .fontSize(24)
        .fontWeight(FontWeight.Bold)
        .fontColor('#F2F7FF')
      Text(this.title)
        .fontSize(12)
        .fontColor('#A8BFD8')
    }
    .padding(14)
    .layoutWeight(1)
    .borderRadius(18)
    .backgroundColor(this.tint)
  }
}

@Component
struct TimelineItem {
  @Prop time: string
  @Prop title: string
  @Prop detail: string
  @Prop level: string

  private levelTint(): string {
    if (this.level === 'error') {
      return '#FF8A80'
    }
    if (this.level === 'warn') {
      return '#F7C873'
    }
    return '#74D3F7'
  }

  build() {
    Row({ space: 10 }) {
      Column() {
        Circle()
          .width(10)
          .height(10)
          .fill(this.levelTint())
        Column()
          .width(2)
          .layoutWeight(1)
          .backgroundColor('rgba(116, 211, 247, 0.35)')
      }
      .height(96)
      .alignItems(HorizontalAlign.Center)

      Column({ space: 6 }) {
        Row({ space: 8 }) {
          Text(this.time)
            .fontSize(11)
            .fontColor('#F7C873')
          Text(this.level.toUpperCase())
            .fontSize(10)
            .fontColor('#04121C')
            .padding({ left: 8, right: 8, top: 4, bottom: 4 })
            .backgroundColor(this.levelTint())
            .borderRadius(999)
        }

        Text(this.title)
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .fontColor('#F2F7FF')

        Text(this.detail)
          .fontSize(12)
          .fontColor('#9FB2C7')
          .lineHeight(18)
      }
      .layoutWeight(1)
      .padding(12)
      .borderRadius(16)
      .backgroundColor('rgba(15, 27, 42, 0.96)')
    }
  }
}

interface TimelineRecord {
  time: string
  title: string
  detail: string
  level: string
}

@Entry
@Component
struct DeepDive {
  @State selectedTab: number = 0
  private hasIngestedOnAppear: boolean = false

  private readonly tabs: string[] = ['概览', '链路', '诊断']
  private readonly timeline: TimelineRecord[] = [
    { time: '10:42:12', title: 'Gateway Discovery Started', detail: '尝试 mDNS 发现，预期在 300ms 内返回可用 endpoint。', level: 'info' },
    { time: '10:42:13', title: 'Fallback to Manual DSN', detail: 'mDNS 未命中，回退 127.0.0.1:18765，继续探测 /v2/gateway/discovery。', level: 'warn' },
    { time: '10:42:14', title: 'Raw Inspector Ingested', detail: '成功上报原始节点树，网关开始标准化映射与 typography 单位收敛。', level: 'info' },
    { time: '10:42:15', title: 'Snapshot Build Completed', detail: 'snapshot 构建完成，包含 textContentAlign / padding / wordBreak 全量字段。', level: 'info' },
  ]

  aboutToAppear(): void {
    if (this.hasIngestedOnAppear) {
      return
    }
    this.hasIngestedOnAppear = true
    void demoRuntime.ingestCurrentViewTreeToManualGateway()
  }

  build() {
    Scroll() {
      Column({ space: 16 }) {
        Column({ space: 10 }) {
          Text('Neptune Deep Dive')
            .fontSize(30)
            .fontWeight(FontWeight.Bold)
            .fontColor('#F2F7FF')

          Text('复杂二级页用于验证视图树采集、文本还原、胶囊标签、时间轴列表和卡片层级表现。')
            .fontSize(14)
            .fontColor('#9FB2C7')
            .lineHeight(20)

          Row({ space: 8 }) {
            ForEach(this.tabs, (tab: string, index: number) => {
              Text(tab)
                .fontSize(12)
                .fontColor(this.selectedTab === index ? '#04121C' : '#9FB2C7')
                .padding({ left: 12, right: 12, top: 8, bottom: 8 })
                .backgroundColor(this.selectedTab === index ? '#74D3F7' : 'rgba(255,255,255,0.09)')
                .borderRadius(999)
                .onClick(() => {
                  this.selectedTab = index
                })
            })
          }
        }
        .padding(20)
        .borderRadius(24)
        .backgroundColor('rgba(9, 18, 31, 0.92)')
        .border({ width: 1, color: 'rgba(104, 143, 176, 0.25)' })

        Column({ space: 12 }) {
          Text('Live Metrics Matrix')
            .fontSize(18)
            .fontWeight(FontWeight.Bold)
            .fontColor('#F2F7FF')

          Row({ space: 10 }) {
            MetricChip({ title: 'queueSize', value: '12', tint: 'rgba(36, 74, 106, 0.82)' })
            MetricChip({ title: 'ingested', value: '128', tint: 'rgba(15, 60, 92, 0.82)' })
          }
          Row({ space: 10 }) {
            MetricChip({ title: 'renderNodes', value: '742', tint: 'rgba(39, 46, 89, 0.82)' })
            MetricChip({ title: 'dropped', value: '0', tint: 'rgba(69, 46, 22, 0.82)' })
          }
        }
        .padding(20)
        .borderRadius(24)
        .backgroundColor('rgba(9, 18, 31, 0.92)')
        .border({ width: 1, color: 'rgba(104, 143, 176, 0.25)' })

        Column({ space: 12 }) {
          Text('Inspector Timeline')
            .fontSize(18)
            .fontWeight(FontWeight.Bold)
            .fontColor('#F2F7FF')

          ForEach(this.timeline, (item: TimelineRecord) => {
            TimelineItem({
              time: item.time,
              title: item.title,
              detail: item.detail,
              level: item.level
            })
          })
        }
        .padding(20)
        .borderRadius(24)
        .backgroundColor('rgba(9, 18, 31, 0.92)')
        .border({ width: 1, color: 'rgba(104, 143, 176, 0.25)' })
      }
      .padding({ top: 24, right: 20, bottom: 28, left: 20 })
      .width('100%')
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#06101A')
  }
}
