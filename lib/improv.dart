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

enum Improvrrors {
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
  Improvrrors _error = Improvrrors.noError;
  // BluetoothService? _svc;
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
    int i = val[0];
    _state = improvState.values[i];
    developer.log(
      "Improv: current state {$i} {$_state}",
    );
    notifyListeners();
  }

  void _getErrorState(List<int> val) {
    _error = Improvrrors.values[val[0]];
    developer.log(
      "Improv: error state {$_error}",
    );
    notifyListeners();
  }

  void _getRPCResult(List<int> val) {
    developer.log(
      "Improv: RPC result {$val}",
    );
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
    flutterBlue.stopScan();
    developer.log("Improv: will connect to {$device.name}");
    await device.connect();
    developer.log("Improv: did connect to {$device.name}");
    List<BluetoothService> bluetoothServices = await device.discoverServices();
    developer.log("Improv: did discover services");
    for (BluetoothService s in bluetoothServices) {
      if (s.uuid == _svcUUID) {
        // _svc = s;
        _chrs = s.characteristics;
        developer.log("Improv: got characteristics");
      }
    }
    developer.log("Improv: found service uuid");
    for (BluetoothCharacteristic c in _chrs) {
      if (c.uuid == _capabilitiesUUID) {
        developer.log("Improv: will read identify property");
        List<int> value = await c.read();
        supportsIdentify = value[0] == 1;
        developer.log("Improv: supports identify {$supportsIdentify}");
      } else if (c.uuid == _currentStateUUID) {
        List<int> value = await c.read();
        _getImprovState(value);
        await c.setNotifyValue(true);
        notifyListeners();
        developer.log("Improv: subscribe to characteristic: current state");
        c.value.listen((value) {
          _getImprovState(value);
        });
      } else if (c.uuid == _errorStateUUID) {
        await c.setNotifyValue(true);
        developer.log("Improv: subscribe to characteristic: error state");
        c.value.listen((value) {
          _getErrorState(value);
        });
      } else if (c.uuid == _RPCResultUUID) {
        developer.log("Improv: subscribe to characteristic: RPC result");
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
    _writeRPCCommand(_makePayload([2, 0]));
  }

  void setSSID(String ssid) {
    _ssid = ssid;
  }

  void setPassword(String password) {
    _password = password;
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
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              hintText: 'Enter SSID',
            ),
            onChanged: (value) => controller.setSSID(value),
          ),
          TextField(
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              hintText: 'Enter password',
            ),
            onChanged: (value) => controller.setPassword(value),
          ),
          ElevatedButton(
              onPressed: () {
                controller.submitCredentials();
              },
              child: const Text("submit")),
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
                    child: const Text("Identify"))
                : const Text(""),
            ElevatedButton(
                onPressed: () {
                  controller.device.disconnect();
                  controller.dispose();
                  Navigator.of(context).pop();
                },
                child: const Text("Cancel")),
          ],
        ),
      ),
    );
  }
}
