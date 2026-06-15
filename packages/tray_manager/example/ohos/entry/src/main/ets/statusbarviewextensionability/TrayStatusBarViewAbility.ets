import { UIExtensionContentSession, Want } from '@kit.AbilityKit';
import StatusBarViewExtensionAbility from '@hms.pcService.StatusBarViewExtensionAbility';

export default class TrayStatusBarViewAbility extends StatusBarViewExtensionAbility {
  onSessionCreate(want: Want, session: UIExtensionContentSession): void {
    session.loadContent('pages/TrayStatusBarPage');
  }
}
