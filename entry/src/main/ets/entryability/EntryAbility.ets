import { AbilityConstant, UIAbility, Want } from '@kit.AbilityKit'
import { window } from '@kit.ArkUI'

export default class EntryAbility extends UIAbility {
  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    console.info(
      `EntryAbility.onCreate, want: ${want.abilityName ?? ''}, launchReason: ${launchParam.launchReason}, lastExitReason: ${launchParam.lastExitReason}`
    )
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    windowStage.loadContent('pages/Index', (err) => {
      if (err.code) {
        console.error(`Failed to load pages/Index, code: ${err.code}, message: ${err.message}`)
        return
      }
      console.info('Harmony demo page loaded successfully.')
    })
  }

  onWindowStageDestroy(): void {
    console.info('EntryAbility.onWindowStageDestroy')
  }
}
