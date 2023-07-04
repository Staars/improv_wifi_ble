// Copyright 2023, Christian Baars
// All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:developer' as developer;
import 'dart:typed_data';
import 'dart:convert';

import 'package:flutter/material.dart'
    show
        BuildContext,
        ChangeNotifier,
        Column,
        Container,
        Dialog,
        ElevatedButton,
        InputDecoration,
        Key,
        MainAxisAlignment,
        Navigator,
        OutlineInputBorder,
        State,
        StatefulWidget,
        Text,
        TextField,
        Widget;
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_svg/flutter_svg.dart';

enum improvState { _, Authorization, Authorized, Provisioning, Provisioned }

enum improvErrors {
  noError,
  invalidPacket,
  unknownCommand,
  connectNotPossible,
  notAuthorized,
  _
}

class Improv extends ChangeNotifier {
  Improv({Key? key, required this.device});

  final FlutterBluePlus flutterBlue = FlutterBluePlus.instance;
  final BluetoothDevice device;
  bool connected = true;
  bool supportsIdentify = false;
  improvState _state = improvState._;
  improvErrors _error = improvErrors.noError;
  BluetoothService? _svc;
  List<BluetoothCharacteristic> _chrs = [];
  String _ssid = '';
  String _password = '';

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

  int _getChecksum(List<int> _list) {
    int _checksum = 0;
    for (int i in _list) {
      _checksum = (_checksum + i) & 0xff;
    }
    return _checksum;
  }

  Uint8List _makePayload(List<int> _val) {
    _val.add(_getChecksum(_val));
    return Uint8List.fromList(_val);
  }

  BluetoothCharacteristic _getChr(Guid _uuid) {
    for (BluetoothCharacteristic c in _chrs) {
      if (c.uuid == _uuid) {
        return c;
      }
    }
    throw ("Improv: missing characteristic!!");
  }

  void _getImprovState(List<int> _val) {
    int _i = _val[0];
    _state = improvState.values[_i];
    developer.log(
      "Improve: current state {$_i} {$_state}",
    );
    notifyListeners();
  }

  void _getErrorState(List<int> _val) {
    _error = improvErrors.values[_val[0]];
    developer.log(
      "Improve: error state {$_val[0]}",
    );
    notifyListeners();
  }

  void _getRPCResult(List<int> _val) {
    developer.log(
      "Improve: RPC result {$_val}",
    );
    notifyListeners();
  }

  void _writeRPCCommand(List<int> _cmd) async {
    BluetoothCharacteristic c = _getChr(_RPCCommandUUID);
    await c.write(_cmd, withoutResponse: true);
    notifyListeners();
  }

  void setup() async {
    flutterBlue.stopScan();
    developer.log("Improve: will connect to {$device.name}");
    await device.connect();
    developer.log("Improve: did connect to {$device.name}");
    List<BluetoothService> bluetoothServices = await device.discoverServices();
    for (BluetoothService s in bluetoothServices) {
      if (s.uuid == _svcUUID) {
        _svc = s;
        _chrs = s.characteristics;
      }
    }
    for (BluetoothCharacteristic c in _chrs) {
      if (c.uuid == _capabilitiesUUID) {
        List<int> _val = await c.read();
        supportsIdentify = _val[0] == 1;
        developer.log("Improve: supports identify {$supportsIdentify}");
      } else if (c.uuid == _currentStateUUID) {
        List<int> _val = await c.read();
        _getImprovState(_val);
        await c.setNotifyValue(true);
        notifyListeners();
        developer.log("Improve: subscribe to characteristic: current state");
        c.value.listen((value) {
          _getImprovState(value);
        });
      } else if (c.uuid == _errorStateUUID) {
        await c.setNotifyValue(true);
        developer.log("Improve: subscribe to characteristic: error state");
        c.value.listen((value) {
          _getErrorState(value);
        });
      } else if (c.uuid == _RPCResultUUID) {
        developer.log("Improve: subscribe to characteristic: RPC result");
        await c.setNotifyValue(true);
        c.value.listen((value) {
          _getRPCResult(value);
        });
      }
    }
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
    Uint8List _cmnd = Uint8List.fromList([2, 0, 0]);
    _cmnd[2] = _getChecksum(_cmnd);
    _writeRPCCommand(_cmnd);
  }

  void setSSID(String ssid) {
    _ssid = ssid;
  }

  void setPassword(String password) {
    _password = password;
  }

  void submitCredentials() {
    List<int> _ssidBytes = utf8.encode(_ssid);
    List<int> _passwordBytes = utf8.encode(_password);
    List<int> _command = [1];
    _command.add(_ssidBytes.length + _passwordBytes.length + 2);
    _command.add(_ssidBytes.length);
    _command += _ssidBytes;
    _command.add(_passwordBytes.length);
    _command += _passwordBytes;
    _command.add(_getChecksum(_command));
    _writeRPCCommand(Uint8List.fromList(_command));
    developer.log("Start commissioning ... {$_command}");
  }
}

class ImprovDialog extends StatefulWidget {
  ImprovDialog({Key? key, required this.controller}) : super(key: key);
  final Improv controller;

  @override
  State<ImprovDialog> createState() =>
      _ImprovDialogState(controller: controller);
}

class _ImprovDialogState extends State<ImprovDialog> {
  _ImprovDialogState({Key? key, required this.controller});
  final String assetName = 'lib/assets/improv-logo.svg';
  final Improv controller;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(() {
      setState(() {});
    });
  }

  Widget _currentDialog(BuildContext context) {
    switch (controller._state) {
      case improvState.Authorization:
      //   return Text("");
      case improvState.Authorized:
        return Column(children: [
          TextField(
            decoration: InputDecoration(
              border: OutlineInputBorder(),
              hintText: 'Enter SSID',
            ),
            onChanged: (value) => controller.setSSID(value),
          ),
          TextField(
            decoration: InputDecoration(
              border: OutlineInputBorder(),
              hintText: 'Enter password',
            ),
            onChanged: (value) => controller.setPassword(value),
          ),
          ElevatedButton(
              onPressed: () {
                controller.submitCredentials();
              },
              child: Text("submit")),
        ]);
      default:
        return (Text(controller.statusMessage()));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: Container(
        // height: 300,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            SvgPicture.asset(assetName,
                semanticsLabel: 'Improv Logo', width: 150, height: 150),
            _currentDialog(context),
            controller.supportsIdentify
                ? ElevatedButton(
                    onPressed: () {
                      controller.identify();
                    },
                    child: Text("Identify"))
                : Text(""),
            ElevatedButton(
                onPressed: () {
                  controller.device.disconnect();
                  controller.dispose();
                  Navigator.of(context).pop();
                },
                child: Text("Cancel")),
          ],
        ),
      ),
    );
  }
}
