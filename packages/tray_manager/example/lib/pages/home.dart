// ignore_for_file: deprecated_member_use

import 'dart:async';
import 'dart:io';

import 'package:bot_toast/bot_toast.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:tray_manager/tray_manager.dart';

const _kIconTypeDefault = 'default';
const _kIconTypeOriginal = 'original';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with TrayListener {
  ValueNotifier<bool> shouldForegroundOnContextMenu = ValueNotifier(false);
  String _iconType = _kIconTypeOriginal;
  Menu? _menu;
  String _lastStatus = 'Initializing tray...';

  Timer? _timer;

  @override
  void initState() {
    trayManager.addListener(this);
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_initializeTray());
    });
  }

  @override
  void dispose() {
    trayManager.removeListener(this);
    super.dispose();
  }

  Future<void> _handleSetIcon(String iconType) async {
    _iconType = iconType;
    String iconPath =
        Platform.isWindows ? 'images/tray_icon.ico' : 'images/tray_icon.png';

    if (_iconType == 'original') {
      iconPath = Platform.isWindows
          ? 'images/tray_icon_original.ico'
          : 'images/tray_icon_original.png';
    }

    try {
      await trayManager.setIcon(iconPath);
    } catch (error, stackTrace) {
      if (kDebugMode) {
        print('setIcon failed: $error');
        print(stackTrace);
      }
      BotToast.showText(text: 'setIcon failed: $error');
    }
  }

  Future<void> _initializeTray() async {
    try {
      _menu = _createExampleMenu();
      await trayManager.setTitle('tray_manager');
      await trayManager.setContextMenu(_menu!);
      await _handleSetIcon(_iconType);
      await trayManager.setToolTip('tray_manager');
      _setStatus('Tray initialized with context menu.');
    } catch (error, stackTrace) {
      if (kDebugMode) {
        print('initialize tray failed: $error');
        print(stackTrace);
      }
      _setStatus('initialize tray failed: $error');
      BotToast.showText(text: 'initialize tray failed: $error');
    }
  }

  void _startIconFlashing() {
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) async {
      _handleSetIcon(
        _iconType == _kIconTypeOriginal
            ? _kIconTypeDefault
            : _kIconTypeOriginal,
      );
    });
    setState(() {});
  }

  void _stopIconFlashing() {
    if (_timer != null && _timer!.isActive) {
      _timer!.cancel();
    }
    setState(() {});
  }

  Menu _createExampleMenu() {
    return Menu(
      items: [
        MenuItem(
          label: 'Look Up "LeanFlutter"',
        ),
        MenuItem(
          label: 'Search with Google',
        ),
        MenuItem.separator(),
        MenuItem(
          label: 'Cut',
        ),
        MenuItem(
          label: 'Copy',
        ),
        MenuItem(
          label: 'Paste',
          disabled: true,
        ),
        MenuItem.submenu(
          label: 'Share',
          submenu: Menu(
            items: [
              MenuItem.checkbox(
                label: 'Item 1',
                checked: true,
                onClick: (menuItem) {
                  if (kDebugMode) {
                    print('click item 1');
                  }
                  menuItem.checked = !(menuItem.checked == true);
                },
              ),
              MenuItem.checkbox(
                label: 'Item 2',
                checked: false,
                onClick: (menuItem) {
                  if (kDebugMode) {
                    print('click item 2');
                  }
                  menuItem.checked = !(menuItem.checked == true);
                },
              ),
            ],
          ),
        ),
        MenuItem.separator(),
        MenuItem.submenu(
          label: 'Font',
          submenu: Menu(
            items: [
              MenuItem.checkbox(
                label: 'Item 1',
                checked: true,
                onClick: (menuItem) {
                  if (kDebugMode) {
                    print('click item 1');
                  }
                  menuItem.checked = !(menuItem.checked == true);
                },
              ),
              MenuItem.checkbox(
                label: 'Item 2',
                checked: false,
                onClick: (menuItem) {
                  if (kDebugMode) {
                    print('click item 2');
                  }
                  menuItem.checked = !(menuItem.checked == true);
                },
              ),
              MenuItem.separator(),
              MenuItem(
                label: 'Item 3',
                checked: false,
              ),
              MenuItem(
                label: 'Item 4',
                checked: false,
              ),
              MenuItem(
                label: 'Item 5',
                checked: false,
              ),
            ],
          ),
        ),
        MenuItem.submenu(
          label: 'Speech',
          submenu: Menu(
            items: [
              MenuItem(
                label: 'Item 1',
              ),
              MenuItem(
                label: 'Item 2',
              ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _handleSetContextMenu() async {
    try {
      _menu = _createExampleMenu();
      await trayManager.setContextMenu(_menu!);
      _setStatus('Context menu set.');
    } catch (error, stackTrace) {
      if (kDebugMode) {
        print('setContextMenu failed: $error');
        print(stackTrace);
      }
      _setStatus('setContextMenu failed: $error');
      BotToast.showText(text: 'setContextMenu failed: $error');
    }
  }

  void _setStatus(String message) {
    if (!mounted) {
      return;
    }
    setState(() {
      _lastStatus = message;
    });
  }

  Widget _buildBody(BuildContext context) {
    return ListView(
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.all(16),
          child: Text(_lastStatus),
        ),
        const Divider(height: 0),
        ListTile(
          title: const Text('destroy'),
          onTap: () {
            trayManager.destroy();
          },
        ),
        const Divider(height: 0),
        ListTile(
          title: const Text('setIcon'),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Builder(
                builder: (_) {
                  bool isFlashing = (_timer != null && _timer!.isActive);
                  return TextButton(
                    onPressed:
                        isFlashing ? _stopIconFlashing : _startIconFlashing,
                    child: isFlashing
                        ? const Text('stop flash')
                        : const Text('start flash'),
                  );
                },
              ),
              TextButton(
                child: const Text('Default'),
                onPressed: () => _handleSetIcon(_kIconTypeDefault),
              ),
              TextButton(
                child: const Text('Original'),
                onPressed: () => _handleSetIcon(_kIconTypeOriginal),
              ),
            ],
          ),
          onTap: () => _handleSetIcon(_kIconTypeDefault),
        ),
        const Divider(height: 0),
        ListTile(
          title: const Text('setIconPosition'),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextButton(
                child: const Text('left'),
                onPressed: () {
                  trayManager.setIconPosition(TrayIconPosition.left);
                },
              ),
              TextButton(
                child: const Text('right'),
                onPressed: () {
                  trayManager.setIconPosition(TrayIconPosition.right);
                },
              ),
            ],
          ),
          onTap: () => _handleSetIcon(_kIconTypeDefault),
        ),
        const Divider(height: 0),
        ListTile(
          title: const Text('setToolTip'),
          onTap: () async {
            try {
              await trayManager.setToolTip('tray_manager');
              _setStatus('ToolTip set: tray_manager');
            } catch (error, stackTrace) {
              if (kDebugMode) {
                print('setToolTip failed: $error');
                print(stackTrace);
              }
              _setStatus('setToolTip failed: $error');
              BotToast.showText(text: 'setToolTip failed: $error');
            }
          },
        ),
        const Divider(height: 0),
        ListTile(
          title: const Text('setTitle'),
          onTap: () async {
            try {
              await trayManager.setTitle('tray_manager');
              _setStatus('Title set: tray_manager');
            } catch (error, stackTrace) {
              if (kDebugMode) {
                print('setTitle failed: $error');
                print(stackTrace);
              }
              _setStatus('setTitle failed: $error');
              BotToast.showText(text: 'setTitle failed: $error');
            }
          },
        ),
        const Divider(height: 0),
        ListTile(
          title: const Text('setContextMenu'),
          onTap: _handleSetContextMenu,
        ),
        const Divider(height: 0),
        ValueListenableBuilder(
          valueListenable: shouldForegroundOnContextMenu,
          builder: (context, bool bringToForeground, Widget? child) {
            return ListTile(
              title: const Text('popUpContextMenu'),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Should bring app to foreground'),
                  Switch(
                    value: bringToForeground,
                    onChanged: (value) {
                      shouldForegroundOnContextMenu.value = !bringToForeground;
                    },
                  ),
                ],
              ),
              onTap: () async {
                try {
                  await trayManager.popUpContextMenu(
                    bringAppToFront: shouldForegroundOnContextMenu.value,
                  );
                  _setStatus('popUpContextMenu completed.');
                } catch (error, stackTrace) {
                  if (kDebugMode) {
                    print('popUpContextMenu failed: $error');
                    print(stackTrace);
                  }
                  _setStatus('popUpContextMenu failed: $error');
                  BotToast.showText(text: 'popUpContextMenu failed: $error');
                }
              },
            );
          },
        ),
        const Divider(height: 0),
        ListTile(
          title: const Text('getBounds'),
          onTap: () async {
            try {
              Rect? bounds = await trayManager.getBounds();
              if (bounds == null) {
                _setStatus('getBounds returned null');
                BotToast.showText(text: 'getBounds returned null');
                return;
              }
              Size size = bounds.size;
              Offset origin = bounds.topLeft;
              final message = 'getBounds: size=$size, origin=$origin';
              _setStatus(message);
              BotToast.showText(
                text: '${size.toString()}\n${origin.toString()}',
              );
            } catch (error, stackTrace) {
              if (kDebugMode) {
                print('getBounds failed: $error');
                print(stackTrace);
              }
              _setStatus('getBounds failed: $error');
              BotToast.showText(text: 'getBounds failed: $error');
            }
          },
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Plugin example app'),
      ),
      body: _buildBody(context),
    );
  }

  @override
  void onTrayIconMouseDown() {
    if (kDebugMode) {
      print('onTrayIconMouseDown');
    }
    unawaited(_popUpContextMenuFromTray());
  }

  Future<void> _popUpContextMenuFromTray() async {
    try {
      await trayManager.popUpContextMenu(
        bringAppToFront: shouldForegroundOnContextMenu.value,
      );
      _setStatus('Tray left click.');
    } catch (error, stackTrace) {
      if (kDebugMode) {
        print('tray popUpContextMenu failed: $error');
        print(stackTrace);
      }
      _setStatus('tray popUpContextMenu failed: $error');
    }
  }

  @override
  void onTrayIconMouseUp() {
    if (kDebugMode) {
      print('onTrayIconMouseUp');
    }
  }

  @override
  void onTrayIconRightMouseDown() {
    if (kDebugMode) {
      print('onTrayIconRightMouseDown');
    }
    // trayManager.popUpContextMenu();
  }

  @override
  void onTrayIconRightMouseUp() {
    if (kDebugMode) {
      print('onTrayIconRightMouseUp');
    }
  }

  @override
  void onTrayMenuItemClick(MenuItem menuItem) {
    if (kDebugMode) {
      print(menuItem.toJson());
    }
    BotToast.showText(
      text: '${menuItem.toJson()}',
    );
    _setStatus('Menu item clicked: ${menuItem.label ?? menuItem.id}');
  }
}
