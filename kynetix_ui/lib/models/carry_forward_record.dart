class CarryForwardRecord {
  final String date;            // Today's date (yyyy-MM-dd) when prompt occurs
  final String yesterdayDate;   // Yesterday's date (yyyy-MM-dd) of the deviation
  final double yesterdayTarget; // Yesterday's calorie target
  final double yesterdayConsumed; // Yesterday's consumed calories
  final double difference;      // yesterdayConsumed - yesterdayTarget
  final double adjustmentAmount; // Cap at ±500 kcal
  final bool accepted;          // Whether the user accepted the adjustment

  const CarryForwardRecord({
    required this.date,
    required this.yesterdayDate,
    required this.yesterdayTarget,
    required this.yesterdayConsumed,
    required this.difference,
    required this.adjustmentAmount,
    required this.accepted,
  });

  Map<String, dynamic> toJson() => {
    'date': date,
    'yesterdayDate': yesterdayDate,
    'yesterdayTarget': yesterdayTarget,
    'yesterdayConsumed': yesterdayConsumed,
    'difference': difference,
    'adjustmentAmount': adjustmentAmount,
    'accepted': accepted,
  };

  factory CarryForwardRecord.fromJson(Map<String, dynamic> json) => CarryForwardRecord(
    date: json['date'] as String,
    yesterdayDate: json['yesterdayDate'] as String,
    yesterdayTarget: (json['yesterdayTarget'] as num).toDouble(),
    yesterdayConsumed: (json['yesterdayConsumed'] as num).toDouble(),
    difference: (json['difference'] as num).toDouble(),
    adjustmentAmount: (json['adjustmentAmount'] as num).toDouble(),
    accepted: json['accepted'] as bool,
  );
}
