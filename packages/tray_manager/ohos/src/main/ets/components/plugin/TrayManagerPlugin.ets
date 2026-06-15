import {
  AbilityAware,
  AbilityPluginBinding,
  Any,
  FlutterAssets,
  FlutterPlugin,
  FlutterPluginBinding,
  MethodCall,
  MethodCallHandler,
  MethodChannel,
  MethodResult,
  Log,
} from '@ohos/flutter_ohos';
import { common } from '@kit.AbilityKit';
import { image } from '@kit.ImageKit';
import emitter from '@ohos.events.emitter';
import display from '@ohos.display';
import dataPreferences from '@ohos.data.preferences';
import statusBarManager from '@hms.pcService.statusBarManager';

const CHANNEL_NAME = 'tray_manager';
const TAG = 'TrayManagerPlugin';
const DEFAULT_ENTRY_ABILITY_NAME = 'EntryAbility';
const DEFAULT_QUICK_OPERATION_TITLE = 'Menu';
const MAX_QUICK_OPERATION_TITLE_LENGTH = 32;
const MAX_MENU_TEXT_LENGTH = 16;
const MAX_ACTION_MENU_ITEM_COUNT = 6;
const MAX_MENU_LOG_CHUNK_LENGTH = 900;
const MENU_PREFERENCES_NAME = 'tray_manager_status_bar_menu';
const MENU_PREFERENCES_ITEMS_KEY = 'items';
const MENU_PREFERENCES_TITLE_KEY = 'title';
const DEFAULT_QUICK_OPERATION_HEIGHT = 300;
const ESTIMATED_STATUS_BAR_ICON_SIZE = 24;
const ESTIMATED_STATUS_BAR_EDGE_MARGIN = 8;
const ESTIMATED_STATUS_BAR_HEIGHT = 48;
const QUICK_OPERATION_MENU_ITEM_CLICK_EVENT = 'tray_manager.quick_operation_menu_item_click';

const EVENT_ON_TRAY_ICON_MOUSE_DOWN = 'onTrayIconMouseDown';
const EVENT_ON_TRAY_ICON_RIGHT_MOUSE_DOWN = 'onTrayIconRightMouseDown';
const EVENT_ON_TRAY_ICON_RIGHT_MOUSE_UP = 'onTrayIconRightMouseUp';
const EVENT_ON_TRAY_MENU_ITEM_CLICK = 'onTrayMenuItemClick';

interface PopupMenuItem {
  id: number;
  title: string;
}

export default class TrayManagerPlugin implements FlutterPlugin, MethodCallHandler, AbilityAware {
  private channel: MethodChannel | null = null;
  private context: common.Context | null = null;
  private abilityContext: common.UIAbilityContext | null = null;
  private flutterAssets: FlutterAssets | null = null;
  private statusBarIcon: statusBarManager.StatusBarIcon | null = null;
  private statusBarGroupMenus: statusBarManager.StatusBarGroupMenu[] = [];
  private contextMenu: Any = null;
  private hoverTips: string = '';
  private quickOperationTitle: string = DEFAULT_QUICK_OPERATION_TITLE;
  private addedToStatusBar: boolean = false;
  private supportsRightMenuClickEvent: boolean = false;
  private lastBounds: Record<string, number> | null = null;
  private onStatusBarIconClick = (eventData: emitter.EventData): void => {
    this.updateLastBoundsFromEventData(eventData);
    if (this.isRightClickEventData(eventData)) {
      this.invokeTrayIconRightClick();
      return;
    }
    this.invokeTrayIconLeftClick();
  };
  private onRightMenuClick = (eventData: emitter.EventData): void => {
    this.updateLastBoundsFromEventData(eventData);
    this.invokeTrayIconRightClick();
    const id = this.getMenuIdFromEventData(eventData);
    if (id === null) {
      return;
    }
    this.channel?.invokeMethod(EVENT_ON_TRAY_MENU_ITEM_CLICK, { 'id': id });
  };
  private onQuickOperationMenuItemClick = (eventData: emitter.EventData): void => {
    const id = this.getMenuIdFromEventData(eventData);
    if (id === null) {
      return;
    }
    this.channel?.invokeMethod(EVENT_ON_TRAY_MENU_ITEM_CLICK, { 'id': id });
  };

  getUniqueClassName(): string {
    return 'TrayManagerPlugin';
  }

  onAttachedToEngine(binding: FlutterPluginBinding): void {
    this.context = binding.getApplicationContext();
    this.flutterAssets = binding.getFlutterAssets();
    this.channel = new MethodChannel(binding.getBinaryMessenger(), CHANNEL_NAME);
    this.channel.setMethodCallHandler(this);
    if (canIUse("SystemCapability.PCService.StatusBarManager")) {
      try {
        statusBarManager.on('statusBarIconClick', this.onStatusBarIconClick);
      } catch (error) {
        Log.e(TAG, `Failed to register status bar icon listener: ${this.errorMessage(error)}`);
      }
      try {
        statusBarManager.on('rightMenuClick', this.onRightMenuClick);
        this.supportsRightMenuClickEvent = true;
      } catch (error) {
        this.supportsRightMenuClickEvent = false;
        Log.w(TAG, `rightMenuClick listener is unavailable: ${this.errorMessage(error)}`);
      }
    } else {
      this.logStatusBarUnsupported('register status bar listeners');
    }
    emitter.on(QUICK_OPERATION_MENU_ITEM_CLICK_EVENT, this.onQuickOperationMenuItemClick);
  }

  onDetachedFromEngine(_binding: FlutterPluginBinding): void {
    if (canIUse("SystemCapability.PCService.StatusBarManager")) {
      try {
        statusBarManager.off('statusBarIconClick', this.onStatusBarIconClick);
      } catch (error) {
        Log.e(TAG, `Failed to unregister status bar icon listener: ${this.errorMessage(error)}`);
      }
      if (this.supportsRightMenuClickEvent) {
        try {
          statusBarManager.off('rightMenuClick', this.onRightMenuClick);
        } catch (error) {
          Log.e(TAG, `Failed to unregister right menu listener: ${this.errorMessage(error)}`);
        }
      }
    } else {
      this.logStatusBarUnsupported('unregister status bar listeners');
    }
    this.supportsRightMenuClickEvent = false;
    emitter.off(QUICK_OPERATION_MENU_ITEM_CLICK_EVENT, this.onQuickOperationMenuItemClick);
    if (this.channel !== null) {
      this.channel.setMethodCallHandler(null);
      this.channel = null;
    }
    this.context = null;
    this.abilityContext = null;
    this.flutterAssets = null;
  }

  onAttachedToAbility(binding: AbilityPluginBinding): void {
    this.abilityContext = binding.getAbility().context as common.UIAbilityContext;
  }

  onDetachedFromAbility(): void {
    this.abilityContext = null;
  }

  onMethodCall(call: MethodCall, result: MethodResult): void {
    this.handleMethodCall(call, result).catch((error: Any) => {
      result.error('error', this.errorMessage(error), null);
    });
  }

  private async handleMethodCall(call: MethodCall, result: MethodResult): Promise<void> {
    switch (call.method) {
      case 'getPlatformVersion':
        result.success('OpenHarmony');
        break;
      case 'destroy':
        this.destroy();
        result.success(true);
        break;
      case 'setIcon':
        await this.setIcon(call);
        result.success(true);
        break;
      case 'setToolTip':
        await this.setToolTip(this.getStringArgument(call, 'toolTip'));
        result.success(true);
        break;
      case 'setTitle':
        this.quickOperationTitle = this.getStringArgument(call, 'title');
        await this.persistQuickOperationMenu();
        if (this.statusBarIcon !== null) {
          this.addOrReplaceStatusBarItem();
        }
        result.success(true);
        break;
      case 'setContextMenu':
        try {
          await this.setContextMenu(call.argument('menu'));
        } catch (error) {
          throw new Error(`setContextMenu failed: ${this.errorMessage(error)}`);
        }
        result.success(true);
        break;
      case 'getBounds':
        result.success(this.getBounds(call));
        break;
      default:
        result.notImplemented();
        break;
    }
  }

  private async setIcon(call: MethodCall): Promise<void> {
    const pixelMap = await this.createPixelMapFromCall(call);
    this.statusBarIcon = {
      white: pixelMap,
      black: pixelMap,
    };

    const context = this.getStatusBarContext();
    if (this.addedToStatusBar && context !== null) {
      if (canIUse("SystemCapability.PCService.StatusBarManager")) {
        try {
          statusBarManager.updateStatusBarIcon(context, this.statusBarIcon);
        } catch (error) {
          this.addedToStatusBar = false;
          throw new Error(`updateStatusBarIcon failed: ${this.errorMessage(error)}`);
        }
      } else {
        throw new Error(this.statusBarUnsupportedMessage('updateStatusBarIcon'));
      }
      return;
    }
    this.addOrReplaceStatusBarItem();
  }

  private async setToolTip(toolTip: string): Promise<void> {
    this.hoverTips = toolTip;
    const context = this.getStatusBarContext();
    if (!this.addedToStatusBar || context === null) {
      return;
    }
    try {
      if (canIUse("SystemCapability.PCService.StatusBarManager")) {
        await statusBarManager.updateStatusBarHoverTips(context, this.hoverTips);
      } else {
        throw new Error(this.statusBarUnsupportedMessage('updateStatusBarHoverTips'));
      }
    } catch (error) {
      try {
        this.addOrReplaceStatusBarItem();
      } catch (fallbackError) {
        throw new Error(
          `setToolTip failed: ${this.errorMessage(error)}; fallback addToStatusBar failed: ${this.errorMessage(fallbackError)}`,
        );
      }
    }
  }

  private async setContextMenu(menu: Any): Promise<void> {
    this.logMenuValue('setContextMenu.menu', menu);
    this.contextMenu = menu;
    this.statusBarGroupMenus = this.createStatusBarGroupMenus(menu);
    await this.persistQuickOperationMenu();
    const context = this.getStatusBarContext();
    Log.i(
      TAG,
      `setContextMenu: groups=${this.statusBarGroupMenus.length}, added=${this.addedToStatusBar}, hasContext=${context !==
        null}`,
    );
    if (!this.addedToStatusBar || context === null) {
      return;
    }
    if (canIUse("SystemCapability.PCService.StatusBarManager")) {
      try {
        statusBarManager.updateStatusBarMenu(context, this.statusBarGroupMenus);
      } catch (error) {
        throw new Error(`updateStatusBarMenu failed: ${this.errorMessage(error)}`);
      }
    } else {
      throw new Error(this.statusBarUnsupportedMessage('updateStatusBarMenu'));
    }
  }


  private destroy(): void {
    const context = this.getStatusBarContext();
    if (context !== null && this.addedToStatusBar) {
      if (canIUse("SystemCapability.PCService.StatusBarManager")) {
        try {
          statusBarManager.removeFromStatusBar(context);
        } catch (error) {
          throw new Error(`removeFromStatusBar failed: ${this.errorMessage(error)}`);
        }
      } else {
        this.logStatusBarUnsupported('removeFromStatusBar');
      }
    }
    this.addedToStatusBar = false;
    this.lastBounds = null;
  }

  private getBounds(call: MethodCall): Record<string, number> | null {
    if (this.statusBarIcon === null) {
      return this.createFallbackBounds();
    }
    if (this.lastBounds !== null) {
      return this.lastBounds;
    }

    try {
      if (!canIUse("SystemCapability.WindowManager.WindowManager.Core")) {
        Log.w(TAG, 'getBounds requires SystemCapability.WindowManager.WindowManager.Core.');
        return this.createFallbackBounds();
      }

      const displayInfo = display.getDefaultDisplaySync();
      const density = this.getDisplayDensity(call, displayInfo.densityPixels);
      const screenWidth = displayInfo.width / density;
      const screenHeight = displayInfo.height / density;
      const availableHeight = displayInfo.availableHeight > 0 ? displayInfo.availableHeight / density : screenHeight;
      const statusBarHeight = this.estimateStatusBarHeight(screenHeight, availableHeight);
      const iconSize = Math.min(ESTIMATED_STATUS_BAR_ICON_SIZE, statusBarHeight);
      const x = Math.max(0, screenWidth - iconSize - ESTIMATED_STATUS_BAR_EDGE_MARGIN);
      const y = Math.max(0, screenHeight - statusBarHeight + ((statusBarHeight - iconSize) / 2));

      return {
        'x': x,
        'y': y,
        'width': iconSize,
        'height': iconSize,
      };
    } catch (error) {
      Log.e(TAG, `getBounds failed: ${this.errorMessage(error)}`);
      return this.createFallbackBounds();
    }
  }

  private createFallbackBounds(): Record<string, number> {
    return {
      'x': 0,
      'y': 0,
      'width': ESTIMATED_STATUS_BAR_ICON_SIZE,
      'height': ESTIMATED_STATUS_BAR_ICON_SIZE,
    };
  }

  private addOrReplaceStatusBarItem(): void {
    if (this.statusBarIcon === null) {
      return;
    }
    const statusBarIcon = this.statusBarIcon;
    const context = this.requireStatusBarContext();

    const quickOperation: statusBarManager.QuickOperation = {
      title: this.toStatusBarTitle(this.quickOperationTitle),
      height: DEFAULT_QUICK_OPERATION_HEIGHT,
    } as statusBarManager.QuickOperation;

    const statusBarItem: statusBarManager.StatusBarItem = {
      icons: statusBarIcon,
      quickOperation: quickOperation,
    };
    if (canIUse("SystemCapability.PCService.StatusBarManager")) {
      if (this.statusBarGroupMenus.length > 0) {
        statusBarItem.statusBarGroupMenu = this.statusBarGroupMenus;
      }
      try {
        Log.i(
          TAG,
          `addToStatusBar: groups=${this.statusBarGroupMenus.length}, hoverTips=${this.hoverTips.length}`,
        );
        statusBarManager.addToStatusBar(context, statusBarItem);
        this.addedToStatusBar = true;
        Log.i(TAG, 'addToStatusBar succeeded.');
      } catch (error) {
        if (this.tryAddStatusBarItemWithPlainMenuAction(context, statusBarIcon, quickOperation, error)) {
          return;
        }
        this.addedToStatusBar = false;
        throw new Error(`addToStatusBar failed: ${this.errorMessage(error)}`);
      }
    } else {
      this.addedToStatusBar = false;
      throw new Error(this.statusBarUnsupportedMessage('addToStatusBar'));
    }
  }

  private tryAddStatusBarItemWithPlainMenuAction(
    context: common.Context,
    statusBarIcon: statusBarManager.StatusBarIcon,
    quickOperation: statusBarManager.QuickOperation,
    originalError: Any,
  ): boolean {
    if (!this.supportsRightMenuClickEvent || this.contextMenu === null) {
      return false;
    }
    const supportsRightMenuClickEvent = this.supportsRightMenuClickEvent;
    this.supportsRightMenuClickEvent = false;
    this.statusBarGroupMenus = this.createStatusBarGroupMenus(this.contextMenu);

    const fallbackStatusBarItem: statusBarManager.StatusBarItem = {
      icons: statusBarIcon,
      quickOperation: quickOperation,
    };
    if (this.statusBarGroupMenus.length > 0) {
      if (canIUse("SystemCapability.PCService.StatusBarManager")) {
        fallbackStatusBarItem.statusBarGroupMenu = this.statusBarGroupMenus;
      }
    }

    try {
      Log.w(
        TAG,
        `addToStatusBar with notifyOnly menu failed: ${this.errorMessage(originalError)}; retrying with plain menu action.`,
      );
      if (canIUse("SystemCapability.PCService.StatusBarManager")) {
        statusBarManager.addToStatusBar(context, fallbackStatusBarItem);
        this.addedToStatusBar = true;
        Log.i(TAG, 'addToStatusBar plain menu fallback succeeded.');
        return true;
      }
      return false;
    } catch (fallbackError) {
      this.supportsRightMenuClickEvent = supportsRightMenuClickEvent;
      this.statusBarGroupMenus = this.createStatusBarGroupMenus(this.contextMenu);
      Log.e(TAG, `addToStatusBar plain menu fallback failed: ${this.errorMessage(fallbackError)}`);
      return false;
    }
  }

  private async createPixelMapFromCall(call: MethodCall): Promise<image.PixelMap> {
    const resourceManager = this.requireContext().resourceManager;
    const candidatePaths = this.createIconCandidatePaths(call);
    let lastError: Any = null;

    for (const candidatePath of candidatePaths) {
      try {
        const fileData = resourceManager.getRawFileContentSync(candidatePath);
        const buffer = fileData.buffer.slice(fileData.byteOffset, fileData.byteOffset + fileData.byteLength);
        const imageSource = image.createImageSource(buffer);
        return await imageSource.createPixelMap();
      } catch (error) {
        lastError = error;
      }
    }

    throw new Error(`Unable to load status bar icon: ${this.errorMessage(lastError)}`);
  }

  private createIconCandidatePaths(call: MethodCall): string[] {
    const candidates: string[] = [];
    const assetPath = this.getStringArgument(call, 'assetPath');
    const iconPath = this.getStringArgument(call, 'iconPath');
    this.pushCandidate(candidates, assetPath);

    if (this.flutterAssets !== null && assetPath.length > 0) {
      this.pushCandidate(candidates, this.flutterAssets.getAssetFilePathByName(assetPath));
    }

    this.pushCandidate(candidates, this.assetPathFromFlutterAssetsMarker(iconPath));
    this.pushCandidate(candidates, iconPath);
    this.pushCandidate(candidates, this.baseName(assetPath));
    this.pushCandidate(candidates, this.baseName(iconPath));
    return candidates;
  }

  private pushCandidate(candidates: string[], candidate: string): void {
    if (candidate.length === 0) {
      return;
    }
    if (candidates.indexOf(candidate) >= 0) {
      return;
    }
    candidates.push(candidate);
  }

  private assetPathFromFlutterAssetsMarker(iconPath: string): string {
    if (iconPath.length === 0) {
      return '';
    }
    const normalized = iconPath.replace(/\\/g, '/');
    const marker = 'flutter_assets/';
    const index = normalized.lastIndexOf(marker);
    if (index < 0) {
      return normalized;
    }
    return normalized.substring(index + marker.length);
  }

  private baseName(filePath: string): string {
    if (filePath.length === 0) {
      return '';
    }
    const normalized = filePath.replace(/\\/g, '/');
    const index = normalized.lastIndexOf('/');
    if (index < 0) {
      return normalized;
    }
    return normalized.substring(index + 1);
  }

  private getDisplayDensity(call: MethodCall, displayDensity: number): number {
    const devicePixelRatio = this.getNumberArgument(call, 'devicePixelRatio', 0);
    if (devicePixelRatio > 0) {
      return devicePixelRatio;
    }
    if (displayDensity > 0) {
      return displayDensity;
    }
    return 1;
  }

  private estimateStatusBarHeight(screenHeight: number, availableHeight: number): number {
    const occupiedHeight = screenHeight - availableHeight;
    if (occupiedHeight >= ESTIMATED_STATUS_BAR_ICON_SIZE) {
      return Math.min(occupiedHeight, ESTIMATED_STATUS_BAR_HEIGHT);
    }
    return ESTIMATED_STATUS_BAR_HEIGHT;
  }

  private updateLastBoundsFromEventData(eventData: emitter.EventData): void {
    const data = this.getEventDataMap(eventData);
    if (data === null) {
      return;
    }
    const x = this.getFirstNumberValue(data, ['x', 'screenX', 'displayX', 'globalX', 'pointerX', 'mouseX']);
    const y = this.getFirstNumberValue(data, ['y', 'screenY', 'displayY', 'globalY', 'pointerY', 'mouseY']);
    if (x === null || y === null) {
      return;
    }
    const iconSize = ESTIMATED_STATUS_BAR_ICON_SIZE;
    this.lastBounds = {
      'x': Math.max(0, x - (iconSize / 2)),
      'y': Math.max(0, y - (iconSize / 2)),
      'width': iconSize,
      'height': iconSize,
    };
  }

  private invokeTrayIconLeftClick(): void {
    this.channel?.invokeMethod(EVENT_ON_TRAY_ICON_MOUSE_DOWN, null);
  }

  private invokeTrayIconRightClick(): void {
    this.channel?.invokeMethod(EVENT_ON_TRAY_ICON_RIGHT_MOUSE_DOWN, null);
    this.channel?.invokeMethod(EVENT_ON_TRAY_ICON_RIGHT_MOUSE_UP, null);
  }

  private isRightClickEventData(eventData: emitter.EventData): boolean {
    const data = this.getEventDataMap(eventData);
    if (data === null) {
      return false;
    }

    const buttonText = this.getFirstStringValue(data, [
      'button',
      'mouseButton',
      'buttonType',
      'mouseButtonType',
      'iconClickType',
      'clickType',
      'type',
      'eventType',
      'action',
    ]);
    if (this.isRightClickText(buttonText)) {
      return true;
    }

    const button = this.getFirstNumberValue(data, [
      'button',
      'mouseButton',
      'buttonId',
      'mouseButtonId',
      'btnId',
    ]);
    return button === 1 || button === 2;
  }

  private getEventDataMap(eventData: emitter.EventData): Record<string, Object> | null {
    if (eventData.data === undefined || eventData.data === null) {
      return null;
    }
    return eventData.data as Record<string, Object>;
  }

  private getFirstNumberValue(data: Record<string, Object>, keys: string[]): number | null {
    for (let index = 0; index < keys.length; index++) {
      const value = this.getNumberValue(data[keys[index]]);
      if (value !== null) {
        return value;
      }
    }
    return null;
  }

  private getFirstStringValue(data: Record<string, Object>, keys: string[]): string {
    for (let index = 0; index < keys.length; index++) {
      const value = this.getStringValue(data[keys[index]]);
      if (value.length > 0) {
        return value;
      }
    }
    return '';
  }

  private isRightClickText(value: string): boolean {
    const normalized = value.toLowerCase();
    return normalized.indexOf('right') >= 0 || normalized.indexOf('secondary') >= 0;
  }

  private createStatusBarGroupMenus(menu: Any): statusBarManager.StatusBarGroupMenu[] {
    this.logMenuValue('createStatusBarGroupMenus.menu', menu);
    const items: Any[] = this.getArrayValue(this.getValue(menu, 'items'));
    const statusBarGroupMenus: statusBarManager.StatusBarGroupMenu[] = [];
    let statusBarMenuItems: statusBarManager.StatusBarMenuItem[] = [];
    for (let index = 0; index < items.length; index++) {
      this.logMenuValue(`createStatusBarGroupMenus.items[${index}]`, items[index]);
      const type: string = this.getStringValue(this.getValue(items[index], 'type'));
      if (type === 'separator') {
        Log.i(TAG, `createStatusBarGroupMenus.separator index=${index}, currentGroupSize=${statusBarMenuItems.length}`);
        if (statusBarMenuItems.length > 0) {
          statusBarGroupMenus.push(statusBarMenuItems);
          statusBarMenuItems = [];
        }
        continue;
      }
      const menuItem: statusBarManager.StatusBarMenuItem | null = this.createStatusBarMenuItem(items[index]);
      if (menuItem !== null) {
        statusBarMenuItems.push(menuItem);
      }
    }
    if (statusBarMenuItems.length > 0) {
      statusBarGroupMenus.push(statusBarMenuItems);
    }
    this.logMenuValue('createStatusBarGroupMenus.result', statusBarGroupMenus);
    return statusBarGroupMenus;
  }

  private createPopupMenuItems(menu: Any): PopupMenuItem[] {
    this.logMenuValue('createPopupMenuItems.menu', menu);
    const popupItems: PopupMenuItem[] = [];
    this.appendPopupMenuItems(popupItems, this.getArrayValue(this.getValue(menu, 'items')), '');
    this.logMenuValue('createPopupMenuItems.result', popupItems);
    return popupItems;
  }

  private appendPopupMenuItems(popupItems: PopupMenuItem[], items: Any[], prefix: string): void {
    for (let index = 0; index < items.length && popupItems.length < MAX_ACTION_MENU_ITEM_COUNT; index++) {
      const item: Any = items[index];
      this.logMenuValue(`appendPopupMenuItems.prefix(${prefix}).items[${index}]`, item);
      const type = this.getStringValue(this.getValue(item, 'type'));
      if (type === 'separator' || this.getBooleanValue(this.getValue(item, 'disabled'))) {
        continue;
      }

      const title = this.joinMenuTitle(prefix, this.createMenuTitle(item));
      if (title.length === 0) {
        continue;
      }

      if (type === 'submenu') {
        const submenu: Any = this.getValue(item, 'submenu');
        this.appendPopupMenuItems(popupItems, this.getArrayValue(this.getValue(submenu, 'items')), title);
        continue;
      }

      const id = this.getMenuId(item);
      if (id === null) {
        continue;
      }
      popupItems.push({
        id: id,
        title: title,
      });
    }
  }


  private async persistQuickOperationMenu(): Promise<void> {
    const context = this.getStatusBarContext();
    if (context === null) {
      return;
    }
    if (!canIUse("SystemCapability.DistributedDataManager.Preferences.Core")) {
      Log.w(TAG, 'Preferences capability is unavailable; quick operation menu cannot be persisted.');
      return;
    }

    const popupItems = this.createPopupMenuItems(this.contextMenu);
    try {
      const preferences = await dataPreferences.getPreferences(context, MENU_PREFERENCES_NAME);
      await preferences.put(MENU_PREFERENCES_ITEMS_KEY, JSON.stringify(popupItems));
      await preferences.put(MENU_PREFERENCES_TITLE_KEY, this.toDisplayTitle(this.quickOperationTitle));
      await preferences.flush();
    } catch (error) {
      Log.e(TAG, `Failed to persist quick operation menu: ${this.errorMessage(error)}`);
    }
  }

  private createStatusBarMenuItem(item: Any): statusBarManager.StatusBarMenuItem | null {
    this.logMenuValue('createStatusBarMenuItem.item', item);
    const type = this.getStringValue(this.getValue(item, 'type'));
    if (type === 'separator' || this.getBooleanValue(this.getValue(item, 'disabled'))) {
      return null;
    }

    const title = this.createMenuTitle(item);
    if (title.length === 0) {
      return null;
    }

    if (type === 'submenu') {
      const subMenuItems = this.createStatusBarSubMenuItems(item, '');
      if (subMenuItems.length === 0) {
        return null;
      }
      return {
        title: this.toMenuText(title),
        subMenu: subMenuItems,
      };
    }

    return {
      title: this.toMenuText(title),
      menuAction: this.createMenuAction(item),
    };
  }

  private createStatusBarSubMenuItems(item: Any, prefix: string): statusBarManager.StatusBarSubMenuItem[] {
    this.logMenuValue(`createStatusBarSubMenuItems.item.prefix(${prefix})`, item);
    const submenu: Any = this.getValue(item, 'submenu');
    this.logMenuValue(`createStatusBarSubMenuItems.submenu.prefix(${prefix})`, submenu);
    const items: Array<Any> = this.getArrayValue(this.getValue(submenu, 'items'));
    const subMenuItems: statusBarManager.StatusBarSubMenuItem[] = [];

    for (let index = 0; index < items.length; index++) {
      const subItem: Any = items[index];
      this.logMenuValue(`createStatusBarSubMenuItems.prefix(${prefix}).items[${index}]`, subItem);
      const type = this.getStringValue(this.getValue(subItem, 'type'));
      if (type === 'separator' || this.getBooleanValue(this.getValue(subItem, 'disabled'))) {
        continue;
      }

      if (type === 'submenu') {
        const nestedPrefix = this.joinMenuTitle(prefix, this.createMenuTitle(subItem));
        subMenuItems.push(...this.createStatusBarSubMenuItems(subItem, nestedPrefix));
        continue;
      }

      const subTitle = this.joinMenuTitle(prefix, this.createMenuTitle(subItem));
      if (subTitle.length === 0) {
        continue;
      }
      subMenuItems.push({
        subTitle: this.toMenuText(subTitle),
        menuAction: this.createMenuAction(subItem),
      });
    }
    return subMenuItems;
  }

  private createMenuAction(item: Any): statusBarManager.StatusBarMenuAction {
    return this.createMenuActionFromId(this.getMenuId(item));
  }

  private createMenuActionFromId(id: number | null): statusBarManager.StatusBarMenuAction {
    const menuAction: statusBarManager.StatusBarMenuAction = {
      abilityName: DEFAULT_ENTRY_ABILITY_NAME,
    };
    if (this.supportsRightMenuClickEvent) {
      return menuAction;
    }
    if (canIUse("SystemCapability.PCService.StatusBarManager")) {
      menuAction.notifyOnly = true;
      menuAction.menuCode = id === null ? '' : id.toString();
    }
    return menuAction;
  }

  private createMenuTitle(item: Any): string {
    const label = this.getStringValue(this.getValue(item, 'label'));
    const type = this.getStringValue(this.getValue(item, 'type'));
    if (type !== 'checkbox') {
      return label;
    }
    return this.getBooleanValue(this.getValue(item, 'checked')) ? `✓ ${label}` : label;
  }

  private joinMenuTitle(prefix: string, title: string): string {
    if (prefix.length === 0) {
      return title;
    }
    if (title.length === 0) {
      return prefix;
    }
    return `${prefix} / ${title}`;
  }

  private toStatusBarTitle(title: string): string {
    const normalized = title.length > 0 ? title : DEFAULT_QUICK_OPERATION_TITLE;
    if (normalized.length <= MAX_QUICK_OPERATION_TITLE_LENGTH) {
      return normalized;
    }
    return normalized.substring(0, MAX_QUICK_OPERATION_TITLE_LENGTH);
  }

  private toDisplayTitle(title: string): string {
    return title.length > 0 ? title : DEFAULT_QUICK_OPERATION_TITLE;
  }

  private toMenuText(text: string): string {
    if (text.length <= MAX_MENU_TEXT_LENGTH) {
      return text;
    }
    return text.substring(0, MAX_MENU_TEXT_LENGTH);
  }


  private getMenuId(item: Any): number | null {
    const id: Any = this.getValue(item, 'id');
    if (typeof id === 'number') {
      return id;
    }
    if (typeof id === 'string' && id.length > 0) {
      const parsed = Number(id);
      return Number.isNaN(parsed) ? null : parsed;
    }
    return null;
  }

  private getMenuIdFromEventData(eventData: emitter.EventData): number | null {
    if (eventData.data === undefined) {
      return null;
    }
    const data: Record<string, Object> = eventData.data as Record<string, Object>;
    const directId = this.getNumberValue(data['id']);
    if (directId !== null) {
      return directId;
    }
    const menuCode: Object | undefined = data['menuCode'];
    if (typeof menuCode === 'number') {
      return menuCode;
    }
    if (typeof menuCode === 'string') {
      const id = Number(menuCode);
      return Number.isNaN(id) ? null : id;
    }
    return null;
  }

  private requireContext(): common.Context {
    const context = this.getStatusBarContext();
    if (context === null) {
      throw new Error('TrayManagerPlugin is not attached to a FlutterEngine.');
    }
    return context;
  }

  private getStatusBarContext(): common.Context | null {
    if (this.abilityContext !== null) {
      return this.abilityContext;
    }
    return this.context;
  }

  private requireStatusBarContext(): common.Context {
    const context = this.getStatusBarContext();
    if (context === null) {
      throw new Error('TrayManagerPlugin is not attached to a UIAbility.');
    }
    return context;
  }

  private getStringArgument(call: MethodCall, key: string): string {
    try {
      return this.getStringValue(call.argument(key));
    } catch (error) {
      Log.e(TAG, `Failed to read string argument "${key}": ${this.errorMessage(error)}`);
      return '';
    }
  }

  private getNumberArgument(call: MethodCall, key: string, defaultValue: number): number {
    try {
      const value = this.getNumberValue(call.argument(key));
      return value !== null ? value : defaultValue;
    } catch (error) {
      Log.e(TAG, `Failed to read number argument "${key}": ${this.errorMessage(error)}`);
      return defaultValue;
    }
  }

  private logMenuValue(label: string, value: Any): void {
    const text: string = this.stringifyMenuValue(value);
    if (text.length <= MAX_MENU_LOG_CHUNK_LENGTH) {
      Log.i(TAG, `${label}: ${text}`);
      return;
    }

    const total: number = Math.ceil(text.length / MAX_MENU_LOG_CHUNK_LENGTH);
    for (let index = 0; index < total; index++) {
      const start: number = index * MAX_MENU_LOG_CHUNK_LENGTH;
      const end: number = Math.min(start + MAX_MENU_LOG_CHUNK_LENGTH, text.length);
      Log.i(TAG, `${label} [${index + 1}/${total}]: ${text.substring(start, end)}`);
    }
  }

  private stringifyMenuValue(value: Any): string {
    if (value === null) {
      return 'null';
    }
    if (value === undefined) {
      return 'undefined';
    }

    try {
      const json: Any = JSON.stringify(this.normalizeMenuValue(value));
      if (typeof json === 'string' && json.length > 0) {
        return json;
      }
    } catch (error) {
      Log.w(TAG, `Failed to stringify menu value: ${this.errorMessage(error)}`);
    }
    return `${value}`;
  }

  private normalizeMenuValue(value: Any): Any {
    if (value === null || value === undefined) {
      return value;
    }
    if (Array.isArray(value)) {
      const result: Any[] = [];
      for (let index = 0; index < value.length; index++) {
        result.push(this.normalizeMenuValue(value[index]));
      }
      return result;
    }
    if (value instanceof Map) {
      const result: Record<string, Any> = {};
      (value as Map<Any, Any>).forEach((entryValue: Any, entryKey: Any): void => {
        result[`${entryKey}`] = this.normalizeMenuValue(entryValue);
      });
      return result;
    }
    return value;
  }

  private getArrayValue(value: Any): Any[] {
    if (Array.isArray(value)) {
      return value;
    }
    return [];
  }

  private getBooleanValue(value: Any): boolean {
    if (typeof value === 'boolean') {
      return value;
    }
    return false;
  }

  private getStringValue(value: Any): string {
    if (typeof value === 'string') {
      return value;
    }
    return '';
  }

  private getNumberValue(value: Any): number | null {
    if (typeof value === 'number') {
      return value;
    }
    if (typeof value === 'string' && value.length > 0) {
      const parsed = Number(value);
      return Number.isNaN(parsed) ? null : parsed;
    }
    return null;
  }

  private getValue(value: Any, key: string): Any {
    if (value === null || value === undefined) {
      return null;
    }
    if (value instanceof Map) {
      return (value as Map<Any, Any>).get(key);
    }
    return value[key];
  }

  private statusBarUnsupportedMessage(operation: string): string {
    return `${operation} requires SystemCapability.PCService.StatusBarManager, but this device does not support it.`;
  }

  private logStatusBarUnsupported(operation: string): void {
    Log.w(TAG, this.statusBarUnsupportedMessage(operation));
  }

  private errorMessage(error: Any): string {
    if (error === null || error === undefined) {
      return 'Unknown error';
    }
    const message: Any = this.getValue(error, 'message');
    const code: Any = this.getValue(error, 'code');
    if (typeof message === 'string' && message.length > 0) {
      if (typeof code === 'number' || typeof code === 'string') {
        return `${message} (code: ${code})`;
      }
      return message;
    }
    if (typeof code === 'number' || typeof code === 'string') {
      return `code: ${code}`;
    }
    return `${error}`;
  }
}
