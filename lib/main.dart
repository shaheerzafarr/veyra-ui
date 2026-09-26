import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/data/local_database.dart';
import 'core/data/repositories.dart';
import 'core/state/veyra_controller.dart';
import 'core/theme/app_theme.dart';
import 'features/app_ui/veyra_feature_screens.dart';
import 'features/chats/chat_home_screen.dart';
import 'features/discovery/discover_people_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final repository = LocalVeyraRepository(VeyraDatabase());
  final controller = VeyraController(
    users: repository,
    conversations: repository,
    messages: repository,
    requests: repository,
    settings: repository,
  );
  await controller.initialize();
  runApp(ProviderScope(
    overrides: [veyraControllerProvider.overrideWith((ref) => controller)],
    child: const VeyraApp(),
  ));
}

class VeyraApp extends StatelessWidget {
  const VeyraApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'Veyra',
        theme: veyraTheme(),
        home: const SplashScreen(),
      );
}

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 360),
  )..forward();

  @override
  void initState() {
    super.initState();
    Future<void>.delayed(const Duration(milliseconds: 620), () {
      if (mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute<void>(builder: (_) => const WelcomeScreen()),
        );
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        body: Center(
          child: FadeTransition(
            opacity: CurvedAnimation(
              parent: _controller,
              curve: Curves.easeOutCubic,
            ),
            child: ScaleTransition(
              scale: Tween<double>(begin: .96, end: 1).animate(
                CurvedAnimation(
                  parent: _controller,
                  curve: Curves.easeOutCubic,
                ),
              ),
              child: const BrandMark(size: 88),
            ),
          ),
        ),
      );
}

class BrandMark extends StatelessWidget {
  const BrandMark({super.key, this.size = 52});
  final double size;

  @override
  Widget build(BuildContext context) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(size * .25),
            child: SizedBox(
              height: size,
              width: size,
              child: Image.asset(
                'assets/branding/veyra-app-icon.png',
                fit: BoxFit.cover,
                filterQuality: FilterQuality.medium,
              ),
            ),
          ),
          SizedBox(height: size * .22),
          Text('veyra',
              style: TextStyle(
                  fontSize: size * .42,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -1)),
        ],
      );
}

class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: VeyraColors.backgroundDeep,
        body: Stack(
          fit: StackFit.expand,
          children: [
            const RepaintBoundary(child: _EmeraldWelcomeBackdrop()),
            SafeArea(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final compact = constraints.maxHeight < 720;
                  return SingleChildScrollView(
                    padding: EdgeInsets.fromLTRB(
                      28,
                      compact ? 30 : 54,
                      28,
                      20,
                    ),
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        minHeight: constraints.maxHeight > (compact ? 50 : 74)
                            ? constraints.maxHeight - (compact ? 50 : 74)
                            : 0,
                      ),
                      child: IntrinsicHeight(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const BrandMark(size: 72),
                            SizedBox(height: compact ? 34 : 52),
                            Text.rich(
                              TextSpan(
                                children: [
                                  const TextSpan(text: 'Conversations,\n'),
                                  TextSpan(
                                    text: 'kept close.',
                                    style: TextStyle(
                                      color:
                                          Theme.of(context).colorScheme.primary,
                                    ),
                                  ),
                                ],
                              ),
                              style: Theme.of(context)
                                  .textTheme
                                  .displayLarge
                                  ?.copyWith(fontSize: compact ? 45 : 54),
                            ),
                            const SizedBox(height: 22),
                            ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 350),
                              child: Text(
                                'A calm, private space for the\npeople you choose.',
                                style: Theme.of(context).textTheme.bodyLarge,
                              ),
                            ),
                            const Spacer(),
                            SizedBox(height: compact ? 46 : 88),
                            _WelcomeAction(
                              label: 'Create an account',
                              leading: Icons.person_add_alt_1_outlined,
                              filled: true,
                              onPressed: () =>
                                  _go(context, const InviteScreen()),
                            ),
                            const SizedBox(height: 14),
                            _WelcomeAction(
                              label: 'I already have an account',
                              leading: Icons.login_rounded,
                              onPressed: () =>
                                  _go(context, const LoginScreen()),
                            ),
                            const SizedBox(height: 24),
                            const Center(
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.lock_outline_rounded,
                                    color: VeyraColors.muted,
                                    size: 17,
                                  ),
                                  SizedBox(width: 9),
                                  Text(
                                    'Invitation-only during early access',
                                    style: TextStyle(
                                      color: VeyraColors.muted,
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      );
}

class _WelcomeAction extends StatelessWidget {
  const _WelcomeAction({
    required this.label,
    required this.leading,
    required this.onPressed,
    this.filled = false,
  });

  final String label;
  final IconData leading;
  final VoidCallback onPressed;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final content = Row(
      children: [
        Icon(leading, size: 22),
        Expanded(child: Text(label, textAlign: TextAlign.center)),
        const Icon(Icons.arrow_forward_rounded, size: 22),
      ],
    );
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(VeyraRadii.pill),
    );

    if (filled) {
      return FilledButton(
        onPressed: onPressed,
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(62),
          shape: shape,
        ),
        child: content,
      );
    }
    return OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        minimumSize: const Size.fromHeight(62),
        shape: shape,
      ),
      child: content,
    );
  }
}

class _EmeraldWelcomeBackdrop extends StatelessWidget {
  const _EmeraldWelcomeBackdrop();

  @override
  Widget build(BuildContext context) => DecoratedBox(
        decoration: const BoxDecoration(
          gradient: RadialGradient(
            center: Alignment(.82, -.35),
            radius: 1.35,
            colors: [
              Color(0xFF06342C),
              VeyraColors.backgroundDeep,
              Color(0xFF020605),
            ],
            stops: [0, .48, 1],
          ),
        ),
        child: CustomPaint(painter: _EmeraldRibbonPainter()),
      );
}

class _EmeraldRibbonPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final glow = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.35
      ..shader = const LinearGradient(
        colors: [Color(0x001CF0B8), Color(0xFF54F6CC), Color(0x001CF0B8)],
      ).createShader(Offset.zero & size)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 7);

    final ribbon = Path()
      ..moveTo(size.width * 1.08, size.height * .12)
      ..cubicTo(
        size.width * .58,
        size.height * .24,
        size.width * .92,
        size.height * .49,
        size.width * .54,
        size.height * .63,
      )
      ..cubicTo(
        size.width * .23,
        size.height * .75,
        size.width * .15,
        size.height * .72,
        -size.width * .08,
        size.height * .88,
      )
      ..cubicTo(
        size.width * .18,
        size.height * .61,
        size.width * .68,
        size.height * .67,
        size.width * 1.08,
        size.height * .37,
      )
      ..close();
    canvas.drawPath(
      ribbon,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
          colors: [
            Color(0x0029E6B2),
            Color(0x7029E6B2),
            Color(0x0809A77F),
          ],
        ).createShader(Offset.zero & size),
    );
    canvas.drawPath(ribbon, glow);

    final lowerSweep = Path()
      ..moveTo(-size.width * .16, size.height * .58)
      ..cubicTo(
        size.width * .3,
        size.height * .68,
        size.width * .5,
        size.height * .82,
        size.width * 1.12,
        size.height * .59,
      )
      ..cubicTo(
        size.width * .74,
        size.height * .87,
        size.width * .24,
        size.height * .71,
        -size.width * .16,
        size.height * .74,
      )
      ..close();
    canvas.drawPath(
      lowerSweep,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: [
            Color(0x0015C996),
            Color(0x5515C996),
            Color(0x0015C996),
          ],
        ).createShader(Offset.zero & size),
    );
    canvas.drawPath(lowerSweep, glow..strokeWidth = .8);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

void _go(BuildContext context, Widget page) =>
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => page));

class InviteScreen extends StatefulWidget {
  const InviteScreen({super.key});
  @override
  State<InviteScreen> createState() => _InviteScreenState();
}

class _InviteScreenState extends State<InviteScreen> {
  final _code = TextEditingController();
  String? _error;
  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AuthScaffold(
        eyebrow: 'EARLY ACCESS',
        title: 'Your invitation\nopens the door.',
        subtitle: 'Enter the code shared with you to join Veyra.',
        child: Column(children: [
          TextField(
              controller: _code,
              textCapitalization: TextCapitalization.characters,
              decoration: InputDecoration(
                  labelText: 'Invitation code',
                  errorText: _error,
                  prefixIcon: const Icon(Icons.key_rounded))),
          const SizedBox(height: 18),
          VeyraButton(
              label: 'Continue',
              onPressed: () {
                setState(() => _error = _code.text.trim().length < 6
                    ? 'Enter a valid invitation code'
                    : null);
                if (_error == null) _go(context, const SignUpScreen());
              }),
        ]),
      );
}

class SignUpScreen extends StatefulWidget {
  const SignUpScreen({super.key});
  @override
  State<SignUpScreen> createState() => _SignUpScreenState();
}

class _SignUpScreenState extends State<SignUpScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  String? _error;
  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AuthScaffold(
        eyebrow: 'CREATE ACCOUNT',
        title: 'Start with\nyour private email.',
        subtitle:
            'Your email is only for signing in and account recovery. It is never shown on your profile.',
        child: Column(children: [
          TextField(
              controller: _email,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(
                  labelText: 'Email address',
                  prefixIcon: Icon(Icons.mail_outline_rounded))),
          const SizedBox(height: 12),
          TextField(
              controller: _password,
              obscureText: true,
              decoration: InputDecoration(
                  labelText: 'Password',
                  errorText: _error,
                  prefixIcon: const Icon(Icons.lock_outline_rounded))),
          const SizedBox(height: 18),
          VeyraButton(
              label: 'Continue',
              onPressed: () {
                final valid =
                    _email.text.contains('@') && _password.text.length >= 8;
                setState(() => _error = valid
                    ? null
                    : 'Use a valid email and at least 8 characters');
                if (valid) _go(context, const VerifyEmailScreen());
              }),
        ]),
      );
}

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AuthScaffold(
      eyebrow: 'WELCOME BACK',
      title: 'Good to see you.',
      subtitle: 'Sign in with your private email address.',
      child: Column(children: [
        TextField(
            controller: _email,
            keyboardType: TextInputType.emailAddress,
            decoration: const InputDecoration(
                labelText: 'Email address',
                prefixIcon: Icon(Icons.mail_outline_rounded))),
        const SizedBox(height: 12),
        TextField(
            controller: _password,
            obscureText: true,
            decoration: const InputDecoration(
                labelText: 'Password',
                prefixIcon: Icon(Icons.lock_outline_rounded))),
        Align(
            alignment: Alignment.centerRight,
            child: TextButton(
                onPressed: () => _go(context, const ForgotPasswordScreen()),
                child: const Text('Forgot password?'))),
        const SizedBox(height: 10),
        VeyraButton(
            label: 'Sign in',
            onPressed: () => _go(context, const MainNavigation())),
      ]));
}

class VerifyEmailScreen extends StatelessWidget {
  const VerifyEmailScreen({super.key});
  @override
  Widget build(BuildContext context) => AuthScaffold(
      eyebrow: 'VERIFY EMAIL',
      title: 'Check your inbox.',
      subtitle: 'We sent a verification link to your private email address.',
      child: Column(children: [
        const Icon(Icons.mark_email_read_outlined,
            color: VeyraColors.emerald, size: 44),
        const SizedBox(height: 18),
        VeyraButton(
            label: 'I’ve verified my email',
            onPressed: () => _go(context, const ProfileSetupScreen())),
        TextButton(
            onPressed: () {}, child: const Text('Resend verification email'))
      ]));
}

class ForgotPasswordScreen extends StatelessWidget {
  const ForgotPasswordScreen({super.key});
  @override
  Widget build(BuildContext context) => AuthScaffold(
      eyebrow: 'ACCOUNT RECOVERY',
      title: 'Reset your password.',
      subtitle: 'We’ll send recovery instructions to your private email.',
      child: Column(children: [
        const TextField(
            keyboardType: TextInputType.emailAddress,
            decoration: InputDecoration(
                labelText: 'Email address',
                prefixIcon: Icon(Icons.mail_outline_rounded))),
        const SizedBox(height: 18),
        VeyraButton(
            label: 'Send recovery link',
            onPressed: () => Navigator.pop(context))
      ]));
}

class ProfileSetupScreen extends StatefulWidget {
  const ProfileSetupScreen({super.key});
  @override
  State<ProfileSetupScreen> createState() => _ProfileSetupScreenState();
}

class _ProfileSetupScreenState extends State<ProfileSetupScreen> {
  final _username = TextEditingController();
  final _name = TextEditingController();
  final _bio = TextEditingController();
  String? _usernameError;
  @override
  void dispose() {
    _username.dispose();
    _name.dispose();
    _bio.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AuthScaffold(
      eyebrow: 'PUBLIC PROFILE',
      title: 'Make it yours.',
      subtitle:
          'Your name and username are visible to people you connect with. Your email stays private.',
      child: Column(children: [
        const CircleAvatar(
            radius: 34,
            backgroundColor: VeyraColors.elevated,
            child:
                Icon(Icons.add_a_photo_outlined, color: VeyraColors.emerald)),
        const SizedBox(height: 18),
        TextField(
            controller: _username,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
                labelText: 'Unique username',
                prefixText: '@',
                errorText: _usernameError,
                suffixIcon: _username.text.length > 2
                    ? const Icon(Icons.check_circle, color: VeyraColors.emerald)
                    : null)),
        const SizedBox(height: 12),
        TextField(
            controller: _name,
            decoration: const InputDecoration(labelText: 'Display name')),
        const SizedBox(height: 12),
        TextField(
            controller: _bio,
            maxLength: 90,
            decoration: const InputDecoration(labelText: 'Bio (optional)')),
        const SizedBox(height: 12),
        VeyraButton(
            label: 'Finish setup',
            onPressed: () {
              final invalid =
                  _username.text.trim().length < 3 || _name.text.trim().isEmpty;
              setState(() => _usernameError = invalid
                  ? 'Choose a username with at least 3 characters'
                  : null);
              if (!invalid) {
                Navigator.of(context).pushAndRemoveUntil(
                    MaterialPageRoute<void>(
                        builder: (_) => const MainNavigation()),
                    (_) => false);
              }
            }),
      ]));
}

class AuthScaffold extends StatelessWidget {
  const AuthScaffold(
      {required this.eyebrow,
      required this.title,
      required this.subtitle,
      required this.child,
      super.key});
  final String eyebrow, title, subtitle;
  final Widget child;
  @override
  Widget build(BuildContext context) => Scaffold(
      appBar: AppBar(
          leading: IconButton(
              icon: const Icon(Icons.arrow_back_rounded),
              onPressed: () => Navigator.maybePop(context))),
      body: SafeArea(
          child: ListView(
              padding: const EdgeInsets.fromLTRB(24, 40, 24, 24),
              children: [
            Text(eyebrow,
                style: const TextStyle(
                    color: VeyraColors.emerald,
                    letterSpacing: 1.6,
                    fontSize: 12,
                    fontWeight: FontWeight.w700)),
            const SizedBox(height: 14),
            Text(title,
                style: const TextStyle(
                    fontSize: 34,
                    height: 1.1,
                    letterSpacing: -1.2,
                    fontWeight: FontWeight.w700)),
            const SizedBox(height: 14),
            Text(subtitle,
                style: const TextStyle(
                    fontSize: 15, color: VeyraColors.muted, height: 1.45)),
            const SizedBox(height: 38),
            child
          ])));
}

class VeyraButton extends StatelessWidget {
  const VeyraButton({required this.label, required this.onPressed, super.key});
  final String label;
  final VoidCallback onPressed;
  @override
  Widget build(BuildContext context) => FilledButton(
      onPressed: onPressed,
      style: FilledButton.styleFrom(
          backgroundColor: VeyraColors.emerald,
          foregroundColor: VeyraColors.background,
          minimumSize: const Size.fromHeight(56),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
      child: Text(label, style: const TextStyle(fontWeight: FontWeight.w700)));
}

class MainNavigation extends StatefulWidget {
  const MainNavigation({super.key});
  @override
  State<MainNavigation> createState() => _MainNavigationState();
}

class _MainNavigationState extends State<MainNavigation> {
  int _index = 0;
  late final PageController _pageController = PageController();
  final _pages = const [
    ChatHomeScreen(),
    VeyraCallsScreen(),
    VeyraSettingsScreen()
  ];

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _selectPage(int value) {
    if (value == _index) return;
    setState(() => _index = value);
    _pageController.animateToPage(
      value,
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
      body: PageView(
          controller: _pageController,
          physics: const NeverScrollableScrollPhysics(),
          onPageChanged: (value) {
            if (value != _index) setState(() => _index = value);
          },
          children: _pages),
      bottomNavigationBar: NavigationBar(
          selectedIndex: _index,
          onDestinationSelected: _selectPage,
          destinations: const [
            NavigationDestination(
                icon: Icon(Icons.chat_bubble_outline_rounded),
                selectedIcon: Icon(Icons.chat_bubble_rounded),
                label: 'Chats'),
            NavigationDestination(
                icon: Icon(Icons.phone_outlined),
                selectedIcon: Icon(Icons.phone_rounded),
                label: 'Calls'),
            NavigationDestination(
                icon: Icon(Icons.settings_outlined),
                selectedIcon: Icon(Icons.settings_rounded),
                label: 'Settings')
          ]));
}

class ChatsScreen extends StatelessWidget {
  const ChatsScreen({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
      appBar: AppBar(
          title: const Text('Chats',
              style: TextStyle(fontWeight: FontWeight.w700)),
          actions: [
            IconButton(
                onPressed: () => _go(context, const DiscoverPeopleScreen()),
                icon: const Icon(Icons.search_rounded),
                tooltip: 'Discover people'),
            IconButton(
                onPressed: () => _go(context, const VeyraGroupsScreen()),
                icon: const Icon(Icons.edit_note_rounded))
          ]),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        ListTile(
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            tileColor: VeyraColors.elevated,
            leading: const CircleAvatar(
                backgroundColor: Color(0xFF315C51),
                child: Icon(Icons.inbox_rounded, color: VeyraColors.emerald)),
            title: const Text('Requests',
                style: TextStyle(fontWeight: FontWeight.w700)),
            subtitle: const Text('New people want to connect'),
            trailing: Container(
                padding: const EdgeInsets.all(6),
                decoration: const BoxDecoration(
                    color: VeyraColors.emerald, shape: BoxShape.circle),
                child: const Text('2',
                    style: TextStyle(
                        color: VeyraColors.background,
                        fontSize: 12,
                        fontWeight: FontWeight.w800))),
            onTap: () => _go(context, const VeyraRequestsScreen())),
        const SizedBox(height: 20),
        const Text('RECENT',
            style: TextStyle(
                color: VeyraColors.muted, fontSize: 12, letterSpacing: 1.3)),
        const SizedBox(height: 8),
        const _ChatTile(
            name: 'Aisha Khan',
            message: 'That sounds perfect — see you then!',
            time: '10:42',
            chat: true),
        const _ChatTile(
            name: 'Design Circle',
            message: 'Maya: I added the latest screens',
            time: '09:18',
            group: true,
            chat: true),
        const _ChatTile(
            name: 'Omar Siddiqui',
            message: 'Voice message',
            time: 'Yesterday',
            unread: true,
            chat: true)
      ]));
}

class _ChatTile extends StatelessWidget {
  const _ChatTile(
      {required this.name,
      required this.message,
      required this.time,
      this.unread = false,
      this.group = false,
      this.chat = false});
  final String name, message, time;
  final bool unread, group, chat;
  @override
  Widget build(BuildContext context) => ListTile(
      onTap: chat
          ? () => _go(
                context,
                VeyraConversationScreen(name: name, group: group),
              )
          : null,
      contentPadding: const EdgeInsets.symmetric(vertical: 5, horizontal: 4),
      leading: CircleAvatar(
          backgroundColor:
              group ? const Color(0xFF4E4667) : const Color(0xFF315C51),
          child: Text(name[0])),
      title: Text(name, style: const TextStyle(fontWeight: FontWeight.w700)),
      subtitle: Text(message,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(color: VeyraColors.muted)),
      trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(time,
                style: const TextStyle(color: VeyraColors.muted, fontSize: 12)),
            if (unread) const SizedBox(height: 6),
            if (unread)
              const CircleAvatar(
                  radius: 9,
                  backgroundColor: VeyraColors.emerald,
                  child: Text('1',
                      style: TextStyle(
                          fontSize: 10, color: VeyraColors.background)))
          ]));
}

class CallsScreen extends StatelessWidget {
  const CallsScreen({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
      appBar: AppBar(
          title: const Text('Calls',
              style: TextStyle(fontWeight: FontWeight.w700))),
      body: const Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.phone_in_talk_outlined, size: 46, color: VeyraColors.muted),
        SizedBox(height: 14),
        Text('No recent calls', style: TextStyle(fontWeight: FontWeight.w700)),
        SizedBox(height: 6),
        Text('Calls with your contacts will appear here.',
            style: TextStyle(color: VeyraColors.muted))
      ])));
}

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
      appBar: AppBar(
          title: const Text('Settings',
              style: TextStyle(fontWeight: FontWeight.w700))),
      body: ListView(padding: const EdgeInsets.all(16), children: const [
        ListTile(
            leading: CircleAvatar(
                radius: 27,
                backgroundColor: Color(0xFF315C51),
                child: Text('S')),
            title: Text('Shaheer Malik',
                style: TextStyle(fontWeight: FontWeight.w700)),
            subtitle: Text('@shaheer')),
        SizedBox(height: 18),
        _SettingTile(
            Icons.person_outline_rounded, 'Profile', 'Name, username and bio'),
        _SettingTile(Icons.lock_outline_rounded, 'Privacy',
            'Discoverability and requests'),
        _SettingTile(Icons.notifications_none_rounded, 'Notifications',
            'Messages and calls'),
        _SettingTile(
            Icons.palette_outlined, 'Appearance', 'Theme and chat display'),
        _SettingTile(Icons.storage_outlined, 'Storage', 'Media and downloads'),
        _SettingTile(Icons.info_outline_rounded, 'About Veyra', 'Version 0.1.0')
      ]));
}

class _SettingTile extends StatelessWidget {
  const _SettingTile(this.icon, this.title, this.subtitle);
  final IconData icon;
  final String title, subtitle;
  @override
  Widget build(BuildContext context) => ListTile(
      contentPadding: const EdgeInsets.symmetric(vertical: 4),
      leading: Icon(icon, color: VeyraColors.emerald),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle:
          Text(subtitle, style: const TextStyle(color: VeyraColors.muted)),
      trailing:
          const Icon(Icons.chevron_right_rounded, color: VeyraColors.muted),
      onTap: () {});
}
