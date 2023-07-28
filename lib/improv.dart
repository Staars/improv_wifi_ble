// Copyright 2023, Christian Baars
// All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:developer' as developer;
import 'dart:typed_data';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_svg/flutter_svg.dart';

enum improvState { _, Authorization, Authorized, Provisioning, Provisioned }

enum Improverrors {
  noError,
  invalidPacket,
  unknownCommand,
  connectNotPossible,
  notAuthorized,
  _
}

class Improv extends ChangeNotifier {
  Improv({Key? key, required this.device});

  bool _disposed = false;
  @override
  void dispose() {
    device.disconnect();
    _disposed = true;
    super.dispose();
  }

  @override
  void notifyListeners() {
    if (!_disposed) {
      super.notifyListeners();
    }
  }

  // final FlutterBluePlus flutterBlue = FlutterBluePlus;
  final BluetoothDevice device;
  bool connected = true;
  bool supportsIdentify = false;
  improvState _state = improvState._;
  Improverrors _error = Improverrors.noError;
  // BluetoothService? _svc;
  List<BluetoothCharacteristic> _chrs = [];
  String _ssid = '';
  String _password = '';
  int _currentReceiveCommand = -1;
  int _currentReceiveBytesLeft = 0;
  final Map _deviceInfo = {};
  List<Map> APList = [];
  final String _wifiScan = "";
  List<int> _msgRXBuffer = [];

  static final Guid _svcUUID = Guid('00467768-6228-2272-4663-277478268000');
  static final Guid _currentStateUUID =
      Guid('00467768-6228-2272-4663-277478268001');
  static final Guid _errorStateUUID =
      Guid('00467768-6228-2272-4663-277478268002');
  static final Guid _RPCCommandUUID =
      Guid('00467768-6228-2272-4663-277478268003');
  static final Guid _RPCResultUUID =
      Guid('00467768-6228-2272-4663-277478268004');
  static final Guid _capabilitiesUUID =
      Guid('00467768-6228-2272-4663-277478268005');
  static final List<Guid> scanFilter = List.from([_svcUUID]);

  int _getChecksum(List<int> list) {
    int checksum = 0;
    for (int i in list) {
      checksum = (checksum + i) & 0xff;
    }
    return checksum;
  }

  Uint8List _makePayload(List<int> val) {
    val.add(_getChecksum(val));
    return Uint8List.fromList(val);
  }

  BluetoothCharacteristic _getChr(Guid uuid) {
    for (BluetoothCharacteristic c in _chrs) {
      if (c.uuid == uuid) {
        return c;
      }
    }
    throw ("Improv: missing characteristic!!");
  }

  void _getImprovState(List<int> val) {
    if (val.isEmpty) {
      return;
    }
    int i = val[0];
    _state = improvState.values[i];
    developer.log(
      "Improv: current state {$i} {$_state}",
    );
    notifyListeners();
  }

  void _getErrorState(List<int> val) {
    if (val.isEmpty) {
      return;
    }
    _error = Improverrors.values[val[0]];
    developer.log(
      "Improv: error state {$_error}",
    );
    notifyListeners();
  }

  void _parseDeviceInfo() {
    var s = String.fromCharCodes(
        _msgRXBuffer.getRange(2, _msgRXBuffer.length - 1));
    var i = 2;

    developer.log("Improv: parse device info: " + s);
    _deviceInfo['firmware'] = String.fromCharCodes(
        _msgRXBuffer.getRange(i + 1, _msgRXBuffer[i] + i + 1));
    i += _msgRXBuffer[i] + 1;
    _deviceInfo['version'] = String.fromCharCodes(
        _msgRXBuffer.getRange(i + 1, _msgRXBuffer[i] + i + 1));
    i += _msgRXBuffer[i] + 1;
    _deviceInfo['chip'] = String.fromCharCodes(
        _msgRXBuffer.getRange(i + 1, _msgRXBuffer[i] + i + 1));
    i += _msgRXBuffer[i] + 1;
    _deviceInfo['name'] = String.fromCharCodes(
        _msgRXBuffer.getRange(i + 1, _msgRXBuffer[i] + i + 1));
    developer.log(_deviceInfo.toString());
    notifyListeners();
  }

  void _parseAPInfo() {
    if (_msgRXBuffer.length < 4) {
      developer.log(APList.toString());
      return;
    }
    var s = String.fromCharCodes(
        _msgRXBuffer.getRange(2, _msgRXBuffer.length - 1));
    var i = 2;
    var AP = {};
    AP['name'] = String.fromCharCodes(
        _msgRXBuffer.getRange(i + 1, _msgRXBuffer[i] + i + 1));
    i += _msgRXBuffer[i] + 1;
    AP['RSSI'] = String.fromCharCodes(
        _msgRXBuffer.getRange(i + 1, _msgRXBuffer[i] + i + 1));
    i += _msgRXBuffer[i] + 1;
    AP['enc'] = String.fromCharCodes(
        _msgRXBuffer.getRange(i + 1, _msgRXBuffer[i] + i + 1));

    // AP['isExpanded'] = false;

    APList.removeWhere(
        (element) => element["name"] == AP["name"]); // remove duplicates

    APList.add(AP);

    developer.log("Improv: parse AP info: " + s);
  }

  void _getRPCResult(List<int> val) {
    developer.log("Improv: RPC received {$val}");
    if (_msgRXBuffer.isEmpty) {
      _msgRXBuffer = val;
      if (val.length > 1) {
        _currentReceiveCommand = val[0];
        _currentReceiveBytesLeft = val[1];
        if (val[1] > _msgRXBuffer.length - 3) {
          return;
        }
      } else if (val.length == 1) {
        _msgRXBuffer = [];
        return;
      }
    } else {
      _msgRXBuffer.addAll(val);
      if (_msgRXBuffer[1] > _msgRXBuffer.length - 2) {
        return;
      }
    }
    if (_msgRXBuffer[1] != _msgRXBuffer.length - 3) {
      developer.log("Improv: RPC wrong message buffer size, discarding ... ");
      developer.log(_msgRXBuffer[1].toString());
      developer.log((_msgRXBuffer.length - 3).toString());
      _msgRXBuffer = [];
      return;
    }
    switch (_msgRXBuffer[0]) {
      case 1:
        break;
      case 3:
        _parseDeviceInfo();
        break;
      case 4:
        _parseAPInfo();
        break;
      default:
        developer.log("Improv: unknown RPC result {$val}");
    }
    _msgRXBuffer = [];
    notifyListeners();
  }

  void _writeRPCCommand(List<int> cmd) async {
    BluetoothCharacteristic c = _getChr(_RPCCommandUUID);
    int bytesLeft = cmd.length;
    developer.log("RPC buffer length: {$bytesLeft}");
    for (int i = 0; i < cmd.length; i += 20) {
      await Future.delayed(const Duration(milliseconds: 50));
      int chunkSize = 20; // always use smallest possible MTU as chunk size
      if (bytesLeft < chunkSize) {
        chunkSize = bytesLeft;
      }
      bytesLeft -= 20;
      await c.write(cmd.sublist(i, i + chunkSize), withoutResponse: true);
    }
    notifyListeners();
  }

  void setup() async {
    FlutterBluePlus.stopScan();
    developer.log("Improv: will connect to {$device.name}");
    await device.connect();
    developer.log("Improv: did connect to {$device.name}");
    List<BluetoothService> bluetoothServices = await device.discoverServices();
    developer.log("Improv: did discover services");
    for (BluetoothService s in bluetoothServices) {
      if (s.serviceUuid == _svcUUID) {
        // _svc = s;
        _chrs = s.characteristics;
        developer.log("Improv: got characteristics");
      }
    }
    developer.log("Improv: found service uuid");
    for (BluetoothCharacteristic c in _chrs) {
      if (c.characteristicUuid == _capabilitiesUUID) {
        developer.log("Improv: will read identify property");
        List<int> value = await c.read();
        if (value.isNotEmpty) {
          supportsIdentify = value[0] == 1;
          developer.log("Improv: supports identify {$supportsIdentify}");
        } else {
          developer.log("Improv: supports identify did not send data");
        }
      } else if (c.characteristicUuid == _currentStateUUID) {
        List<int> value = await c.read();
        _getImprovState(value);
        notifyListeners();
        developer.log("Improv: subscribe to characteristic: current state");
        c.onValueReceived.listen((value) {
          _getImprovState(value);
        });
        await c.setNotifyValue(true);
      } else if (c.characteristicUuid == _errorStateUUID) {
        developer.log("Improv: subscribe to characteristic: error state");
        c.onValueReceived.listen((value) {
          _getErrorState(value);
        });
        await c.setNotifyValue(true);
      } else if (c.characteristicUuid == _RPCResultUUID) {
        developer.log("Improv: subscribe to characteristic: RPC result");
        c.onValueReceived.listen((value) {
          _getRPCResult(value);
        });
        await c.setNotifyValue(true);
      }
    }
    Future.delayed(const Duration(milliseconds: 500), () {
      requestDeviceInfo();
    });
    // requestWifiScan();
  }

  String statusMessage() {
    switch (_state) {
      case improvState.Authorization:
        return "Awaiting authorization via physical interaction.";
      case improvState.Authorized:
        return "Ready to accept credentials.";
      case improvState.Provisioning:
        return "Credentials received, attempt to connect.";
      case improvState.Provisioned:
        return "Connection successful.";
      default:
        return "!! Unknown state !!";
    }
  }

  void identify() {
    _writeRPCCommand(_makePayload([2, 0]));
  }

  void requestDeviceInfo() {
    _writeRPCCommand(_makePayload([3, 0]));
    developer.log("Improv: Request device info ...");
  }

  void requestWifiScan() {
    _writeRPCCommand(_makePayload([4, 0]));
    developer.log("Improv: Request Wifi scan ... ");
  }

  void setSSID(String ssid) {
    _ssid = ssid;
    notifyListeners();
    developer.log("SSID is now: " + _ssid);
  }

  void setPassword(String password) {
    _password = password;
  }

  void startWifiScan() {
    // APList = [];
    requestWifiScan();
  }

  void submitCredentials() {
    List<int> ssidBytes = utf8.encode(_ssid);
    List<int> passwordBytes = utf8.encode(_password);
    List<int> command = [1];
    command.add(ssidBytes.length + passwordBytes.length + 2);
    command.add(ssidBytes.length);
    command += ssidBytes;
    command.add(passwordBytes.length);
    command += passwordBytes;
    command.add(_getChecksum(command));
    _writeRPCCommand(Uint8List.fromList(command));
    developer.log("Start commissioning ... {$command}");
  }
}

class ImprovDialog extends StatefulWidget {
  const ImprovDialog({Key? key, required this.controller}) : super(key: key);
  final Improv controller;

  @override
  State<ImprovDialog> createState() =>
      _ImprovDialogState(controller: controller);
}

class _ImprovDialogState extends State<ImprovDialog> {
  _ImprovDialogState({Key? key, required this.controller});
  final String assetName = 'lib/assets/improv-logo.svg';
  final Improv controller;
  final TextEditingController ssidController = TextEditingController();

  @override
  void initState() {
    super.initState();
    controller.addListener(() {
      setState(() {});
    });
  }

  @override
  dispose() {
    controller.removeListener(() {
      setState;
    });
    controller.dispose();
    super.dispose();
  }

  Widget _showDevInfo(BuildContext context) {
    if (controller._deviceInfo.isEmpty) {
      return const Text("No device info available");
    } else {
      return Column(
        children: [
          Text("Firmware: " + controller._deviceInfo["firmware"]),
          Text("Version: " + controller._deviceInfo["version"]),
          Text("Chip: " + controller._deviceInfo["chip"]),
          Text("Device name: " + controller._deviceInfo["name"]),
        ],
      );
    }
  }

  Widget _showShowScan(BuildContext context) {
    if (controller._wifiScan == "") {
      return Column(children: [
        Tooltip(
          message: "Ask the Improv device to scan for WiFi access points",
          child: ElevatedButton(
              onPressed: () {
                controller.startWifiScan();
              },
              child: const Text("Request WiFi scan")),
        ),
        const SizedBox(height: 20),
      ]);
    } else {
      return const Text("");
    }
  }

  Widget _getWifiIcon(String RSSI) {
    final strength = int.parse(RSSI);
    if (strength < -90) {
      return const Icon(Icons.network_wifi_1_bar);
    } else if (strength < -80) {
      return const Icon(Icons.network_wifi_2_bar);
    } else if (strength < -70) {
      return const Icon(Icons.network_wifi_3_bar);
    } else {
      return const Icon(Icons.signal_wifi_4_bar);
    }
  }

  Widget _getEncIcon(String enc) {
    if (enc == "YES") {
      return const Icon(Icons.wifi_password);
    } else {
      return const Icon(Icons.no_encryption);
    }
  }

  Widget _SSIDSelector(BuildContext context) {
    if (controller.APList.isEmpty) {
      return TextFormField(
        decoration: const InputDecoration(
          filled: true,
          hintText: 'Enter SSID...',
          labelText: "SSID",
        ),
        onChanged: (value) => controller.setSSID(value),
      );
    } else {
      final List<DropdownMenuItem<String>> APentries =
          <DropdownMenuItem<String>>[];
      for (final Map AP in controller.APList) {
        APentries.add(DropdownMenuItem<String>(
            value: AP["name"],
            child: Stack(
              children: [
                Align(
                  alignment: const Alignment(-1, 0),
                  child: Text(AP["name"]),
                ),
                Align(
                    alignment: const Alignment(0.6, 0),
                    child: _getWifiIcon(AP["RSSI"])),
                Align(
                    alignment: const Alignment(0.8, 0),
                    child: _getEncIcon(AP["enc"])),
              ],
            )));
        developer.log(AP["name"]);
      }
      developer.log(APentries.toString());
      return DropdownButtonFormField<String>(
        isExpanded: true,
        items: APentries,
        decoration: const InputDecoration(
          filled: true,
          hintText: 'Enter SSID...',
          labelText: "SSID",
        ),
        onChanged: (String? ssid) {
          setState(() {
            if (ssid != null) {
              controller.setSSID(ssid);
            }
          });
        },
      );
    }
  }

  Widget _currentDialog(BuildContext context) {
    switch (controller._state) {
      case improvState.Authorization:
      //   return Text("");
      case improvState.Authorized:
        return Column(children: [
          _SSIDSelector(context),
          TextFormField(
            decoration: const InputDecoration(
              filled: true,
              hintText: 'Enter Password...',
              labelText: 'Password',
            ),
            onChanged: (value) => controller.setPassword(value),
          ),
          const SizedBox(height: 20),
          Tooltip(
            message:
                "Pass WiFi credentials to the Improv device, may trigger a reboot on success",
            child: ElevatedButton(
                onPressed: () {
                  controller.submitCredentials();
                },
                child: const Text("Submit credentials")),
          ),
        ]);
      default:
        return (Text(controller.statusMessage()));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => Navigator.pushNamedAndRemoveUntil(
                context, '/home', (route) => false)),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: const Text('Commissioning'),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 240, maxWidth: 600),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              ...[
                SvgPicture.asset(assetName,
                    semanticsLabel: 'Improv Logo', width: 150, height: 150),
                _showDevInfo(context),
                _currentDialog(context),
                _showShowScan(context),
              ].expand(
                (widget) => [
                  widget,
                  const SizedBox(
                    height: 24,
                  )
                ],
              )
            ],
          ),
        ),
      ),
    );
  }
}
