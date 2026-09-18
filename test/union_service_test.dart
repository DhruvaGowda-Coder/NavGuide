import 'package:flutter_test/flutter_test.dart';
import 'package:navguide/domain/union_models.dart';
import 'package:navguide/device/unions/union_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('UnionService ownership verification logic', () {
    final service = UnionService();
    final dummyUnion = TravelUnionGroup(
      id: 'test_u_999',
      title: 'Bengaluru to Nandi Hills',
      fromLocation: 'Bengaluru',
      toLocation: 'Nandi Hills',
      departureDateStr: 'Tomorrow · 05:30 AM',
      category: VehicleCategory.bike,
      hostName: 'TestHost',
      hostMobile: '9900112233',
      hostEmail: 'testhost@gmail.com',
      joinCode: 'NANDI1',
      members: [],
      maxMembers: 10,
      createdAt: DateTime.now(),
    );

    // Random user without matching email/id should not be owner
    expect(service.isOwner(dummyUnion), isFalse);
  });
}
