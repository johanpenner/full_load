import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class NewLoadEntryPage extends StatefulWidget {
  const NewLoadEntryPage({super.key});

  @override
  State<NewLoadEntryPage> createState() => _NewLoadEntryPageState();
}

class _NewLoadEntryPageState extends State<NewLoadEntryPage> {
  final _formKey = GlobalKey<FormState>();

  // Form fields
  String? selectedClient;
  String? selectedDriver;
  String? equipmentType;
  String? loadNumber;
  String? bolNumber;
  String? poNumber;
  String? projectNumber;
  DateTime? pickupDate;
  DateTime? deliveryDate;

  bool isMultiPickup = false;
  bool isMultiDrop = false;
  List<String> pickupLocations = [''];
  List<String> dropLocations = [''];

  final List<String> clients = ['Stella Jones', 'Durisol', 'Compass Minerals'];
  final List<String> drivers = ['John Doe', 'Jane Smith', 'Elvin Penner'];

  Future<void> _pickDate({
    required bool isPickup,
  }) async {
    final result = await showDatePicker(
      context: context,
      firstDate: DateTime(2023),
      lastDate: DateTime(2030),
      initialDate: DateTime.now(),
    );

    if (result != null) {
      setState(() {
        if (isPickup) {
          pickupDate = result;
        } else {
          deliveryDate = result;
        }
      });
    }
  }

  Future<void> _saveLoadToFirestore() async {
    final doc = FirebaseFirestore.instance.collection('loads').doc();

    await doc.set({
      'loadNumber': loadNumber,
      'projectNumber': projectNumber,
      'bolNumber': bolNumber,
      'poNumber': poNumber,
      'client': selectedClient,
      'driver': selectedDriver,
      'equipmentType': equipmentType,
      'pickupDate': pickupDate?.toIso8601String(),
      'deliveryDate': deliveryDate?.toIso8601String(),
      'pickupLocations': pickupLocations,
      'dropLocations': dropLocations,
      'isMultiPickup': isMultiPickup,
      'isMultiDrop': isMultiDrop,
      'createdAt': Timestamp.now(),
    });

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('✅ Load saved to Firestore')),
    );

    Navigator.pop(context); // go back after save
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('New Load Entry')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(children: [
            const Text('Load Info', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            TextFormField(
              decoration: const InputDecoration(labelText: 'Load Number'),
              onChanged: (val) => loadNumber = val,
            ),
            TextFormField(
              decoration: const InputDecoration(labelText: 'Project Number'),
              onChanged: (val) => projectNumber = val,
            ),
            TextFormField(
              decoration: const InputDecoration(labelText: 'BOL Number'),
              onChanged: (val) => bolNumber = val,
            ),
            TextFormField(
              decoration: const InputDecoration(labelText: 'PO Number'),
              onChanged: (val) => poNumber = val,
            ),
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(
              value: selectedClient,
              decoration: const InputDecoration(labelText: 'Client'),
              items: clients.map((client) {
                return DropdownMenuItem(value: client, child: Text(client));
              }).toList(),
              onChanged: (val) => setState(() => selectedClient = val),
            ),
            DropdownButtonFormField<String>(
              value: selectedDriver,
              decoration: const InputDecoration(labelText: 'Driver'),
              items: drivers.map((driver) {
                return DropdownMenuItem(value: driver, child: Text(driver));
              }).toList(),
              onChanged: (val) => setState(() => selectedDriver = val),
            ),
            TextFormField(
              decoration: const InputDecoration(labelText: 'Equipment Type'),
              onChanged: (val) => equipmentType = val,
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: Text(pickupDate != null
                      ? 'Pickup: ${DateFormat('yMMMd').format(pickupDate!)}'
                      : 'Select Pickup Date'),
                ),
                IconButton(
                  onPressed: () => _pickDate(isPickup: true),
                  icon: const Icon(Icons.calendar_today),
                ),
              ],
            ),
            Row(
              children: [
                Expanded(
                  child: Text(deliveryDate != null
                      ? 'Delivery: ${DateFormat('yMMMd').format(deliveryDate!)}'
                      : 'Select Delivery Date'),
                ),
                IconButton(
                  onPressed: () => _pickDate(isPickup: false),
                  icon: const Icon(Icons.calendar_month),
                ),
              ],
            ),

            const SizedBox(height: 20),
            CheckboxListTile(
              title: const Text('Multiple Pickup Locations'),
              value: isMultiPickup,
              onChanged: (val) {
                setState(() {
                  isMultiPickup = val ?? false;
                  if (!isMultiPickup) pickupLocations = [''];
                });
              },
            ),
            ...pickupLocations.map((loc) {
              int i = pickupLocations.indexOf(loc);
              return TextFormField(
                decoration: InputDecoration(labelText: 'Pickup Address ${i + 1}'),
                onChanged: (val) => pickupLocations[i] = val,
              );
            }).toList(),
            if (isMultiPickup)
              TextButton(
                onPressed: () => setState(() => pickupLocations.add('')),
                child: const Text('Add Pickup'),
              ),

            const SizedBox(height: 20),
            CheckboxListTile(
              title: const Text('Multiple Drop Locations'),
              value: isMultiDrop,
              onChanged: (val) {
                setState(() {
                  isMultiDrop = val ?? false;
                  if (!isMultiDrop) dropLocations = [''];
                });
              },
            ),
            ...dropLocations.map((loc) {
              int i = dropLocations.indexOf(loc);
              return TextFormField(
                decoration: InputDecoration(labelText: 'Drop Address ${i + 1}'),
                onChanged: (val) => dropLocations[i] = val,
              );
            }).toList(),
            if (isMultiDrop)
              TextButton(
                onPressed: () => setState(() => dropLocations.add('')),
                child: const Text('Add Drop'),
              ),

            const SizedBox(height: 30),
            ElevatedButton.icon(
              onPressed: () {
                if (_formKey.currentState!.validate()) {
                  _saveLoadToFirestore();
                }
              },
              icon: const Icon(Icons.save),
              label: const Text('Save Load'),
            )
          ]),
        ),
      ),
    );
  }
}
