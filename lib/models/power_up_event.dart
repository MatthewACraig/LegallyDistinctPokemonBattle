enum PowerUpType { heal, shield, boost }

class PowerUpEvent {
  const PowerUpEvent(this.type);

  final PowerUpType type;

  static PowerUpEvent? fromPayload(String payload) {
    final normalized = payload.trim().toLowerCase();
    switch (normalized) {
      case 'heal':
        return const PowerUpEvent(PowerUpType.heal);
      case 'shield':
        return const PowerUpEvent(PowerUpType.shield);
      case 'boost':
        return const PowerUpEvent(PowerUpType.boost);
      default:
        return null;
    }
  }
}
