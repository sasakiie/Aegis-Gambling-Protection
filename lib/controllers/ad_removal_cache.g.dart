// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'ad_removal_cache.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class AdCacheEntryAdapter extends TypeAdapter<AdCacheEntry> {
  @override
  final int typeId = 1;

  @override
  AdCacheEntry read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return AdCacheEntry(
      domain: fields[0] as String,
      selectors: (fields[1] as List).cast<String>(),
      isGambling: fields[2] as bool,
      cachedAt: fields[3] as DateTime,
      missCount: fields[4] as int,
      needsReview: fields[5] as bool,
    );
  }

  @override
  void write(BinaryWriter writer, AdCacheEntry obj) {
    writer
      ..writeByte(6)
      ..writeByte(0)
      ..write(obj.domain)
      ..writeByte(1)
      ..write(obj.selectors)
      ..writeByte(2)
      ..write(obj.isGambling)
      ..writeByte(3)
      ..write(obj.cachedAt)
      ..writeByte(4)
      ..write(obj.missCount)
      ..writeByte(5)
      ..write(obj.needsReview);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AdCacheEntryAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
