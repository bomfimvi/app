import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/svg.dart';
import 'package:humhub/pages/settings/settings.dart';
import 'package:humhub/pages/web_view.dart';
import 'package:humhub/util/const.dart';
import 'package:humhub/util/loading_provider.dart';
import 'package:humhub/util/openers/opener_controller.dart';
import 'package:humhub/util/openers/universal_opener_controller.dart';
import 'package:loggy/loggy.dart';
import 'package:rive/rive.dart' as rive;

class OpenerPage extends ConsumerStatefulWidget {
  const OpenerPage({super.key});
  static const String path = '/';

  @override
  OpenerPageState createState() => OpenerPageState();
}

class OpenerPageState extends ConsumerState<OpenerPage> with SingleTickerProviderStateMixin {
  late OpenerController openerControlLer;

  @override
  void initState() {
    super.initState();
    openerControlLer = OpenerController(ref: ref);
    openerControlLer.setForwardAnimation(rive.SimpleAnimation('animation', autoplay: false));
    openerControlLer.setReverseAnimation(rive.SimpleAnimation('animation', autoplay: true));
  }

  // --- FUNÇÃO PARA ABRIR OS LINKS ---
  Future<void> _abrirLink(String url) async {
    UniversalOpenerController controller = UniversalOpenerController(url: url);
    try {
      await controller.initHumHub();
      if (mounted) {
        LoadingProvider.of(ref).dismissAll();
        Navigator.of(context).pushNamed(WebView.path, arguments: controller);
      }
    } catch (e) {
      logError('Erro ao conectar: $e');
      if (mounted) {
        LoadingProvider.of(ref).dismissAll();
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Erro de conexão. Verifique sua internet.')));
      }
    }
  }

  // --- VISUAL DO NOVO BOTÃO ELEGANTE ---
   Widget _buildMenuButton(BuildContext context, {required String label, required IconData icon, required VoidCallback onTap}) {
    final primaryColor = Theme.of(context).primaryColor;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(20),
          child: Ink(
            padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: Colors.grey.withOpacity(0.15),
                  spreadRadius: 1,
                  blurRadius: 10,
                  offset: const Offset(0, 4), // Sombra suave para baixo
                ),
              ],
               border: Border.all(color: primaryColor.withOpacity(0.1), width: 1),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, color: primaryColor, size: 28),
                const SizedBox(width: 15),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: primaryColor, // Texto na cor do tema
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Stack(
        children: [
          // Fundo animado
          rive.RiveAnimation.asset(
            Assets.openerAnimationForward,
            fit: BoxFit.fill,
            controllers: [openerControlLer.animationForwardController],
          ),
          rive.RiveAnimation.asset(
            Assets.openerAnimationReverse,
            fit: BoxFit.fill,
            controllers: [openerControlLer.animationReverseController],
          ),
          
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 30.0),
              child: Column(
                children: [
                  // Configurações
                  Align(
                    alignment: Alignment.topRight,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 16.0),
                      child: IconButton(
                        icon: SvgPicture.asset(Assets.settings, width: 26, height: 26, colorFilter: ColorFilter.mode(Theme.of(context).primaryColor, BlendMode.srcIn)),
                        onPressed: () => Navigator.of(context).pushNamed(SettingsPage.path),
                      ),
                    ),
                  ),

                  const Spacer(flex: 1),

                  // Logo Centralizado
                  Center(
                    child: SizedBox(
                      height: 130,
                      child: Image.asset(Assets.logo),
                    ),
                  ),

                  const SizedBox(height: 50), // Espaço entre logo e botões

                  // --- NOVOS BOTÕES ELEGANTES ---
                  _buildMenuButton(
                    context,
                    label: "SIG-Sistema Integrado de Gestão",
                    icon: Icons.cloud_done_outlined, // Ícone de nuvem
                    onTap: () => _abrirLink("https://drivetriunfante.com.br"),
                  ),

                  _buildMenuButton(
                    context,
                    label: "LinkUP",
                    icon: Icons.assignment_outlined, // Ícone de prancheta
                    onTap: () => _abrirLink("https://drivetriunfante.com.br/solicitacoes.php"),
                  ),
                   // -----------------------------

                  const Spacer(flex: 2),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    openerControlLer.dispose();
    super.dispose();
  }
}