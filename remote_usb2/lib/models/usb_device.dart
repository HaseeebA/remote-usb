class USBDevice {
  final String id;
  final String name;
  final String description;
  bool isShared;

  USBDevice({
    required this.id,
    required this.name,
    required this.description,
    this.isShared = false,
  });

  factory USBDevice.fromJson(Map<String, dynamic> json) => USBDevice(
    id: json['id'],
    name: json['name'],
    description: json['description'],
    isShared: json['isShared'],
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'description': description,
    'isShared': isShared,
  };
}