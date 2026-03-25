import 'package:flutter_test/flutter_test.dart';
import 'package:aegis_prog/main.dart';
import 'package:aegis_prog/controllers/dashboard_controller.dart';

void main() {
  testWidgets('AEGIS Dashboard renders correctly', (WidgetTester tester) async {
    final controller = DashboardController();
    await tester.pumpWidget(AegisApp(dashboardController: controller));

    // Verify the app title appears
    expect(find.text('AEGIS'), findsOneWidget);

    // Verify both toggles are present
    expect(find.text('Ad Blocker'), findsOneWidget);
    expect(find.text('Gambling Protection'), findsOneWidget);

    // Verify live log panel exists
    expect(find.text('LIVE LOG'), findsOneWidget);
  });
}
