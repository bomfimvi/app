import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:humhub/l10n/generated/app_localizations.dart';
import 'package:flutter_svg/svg.dart';
import 'package:humhub/pages/settings/settings.dart';
import 'package:humhub/pages/web_view.dart';
import 'package:humhub/util/const.dart';
import 'package:humhub/util/loading_provider.dart';
import 'package:humhub/util/openers/opener_controller.dart';
import 'package:humhub/util/openers/universal_opener_controller.dart';
import 'package:humhub/util/providers.dart';
import 'package:humhub/util/storage_service.dart';
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
    // Inicia as animações do logo
    openerControlLer.setForwardAnimation(rive.SimpleAnimation('animation', autoplay: false));
    openerControlLer.setReverseAnimation(rive.SimpleAnimation('animation', autoplay: true));
  }

  // --- FUNÇÃO PARA ABRIR OS LINKS ---
  Future<void> _abrirLink(String url) async {
    // Mostra carregando (opcional, depende da sua implementação de LoadingProvider)
    // LoadingProvider.of(ref).showLoading(); 
    
    UniversalOpenerController controller = UniversalOpenerController(url: url);
    try {
      await controller.initHumHub();
      if (mounted) {
        LoadingProvider.of(ref).dismissAll();
        // Navega para o site
        Navigator.of(context).pushNamed(WebView.path, arguments: controller);
      }
    } catch (e) {
      logError('Erro ao conectar: $e');
      if (mounted) {
        LoadingProvider.of(ref).dismissAll();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao conectar: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Stack(
        children: [
          // Fundo animado (Rive)
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
          
          // Conteúdo da Tela
          SafeArea(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // 1. Botão de Configurações (Canto superior direito)
                Align(
                  alignment: Alignment.topRight,
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: IconButton(
                      icon: SvgPicture.asset(Assets.settings, width: 26, height: 26),
                      onPressed: () => Navigator.of(context).pushNamed(SettingsPage.path),
                    ),
                  ),
                ),

                // 2. Logo (Centralizado)
                Expanded(
                  flex: 4,
                  child: Center(
                    child: SizedBox(
                      height: 120,
                      width: 250,
                      child: Image.asset(Assets.logo),
                    ),
                  ),
                ),

                // 3. SEUS DOIS BOTÕES NOVOS
                Expanded(
                  flex: 6,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 40),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.start,
                      children: [
                        const SizedBox(height: 20),
                        
                        // --- BOTÃO 1: DRIVE ---
                        SizedBox(
                          width: double.infinity,
                          height: 55,
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Theme.of(context).primaryColor, // Cor vermelha do tema
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                            ),
                            onPressed: () => _abrirLink("https://drivetriunfante.com.br"),
                            child: const Text(
                              "Acessar Drive",
                              style: TextStyle(fontSize: 18, color: Colors.white, fontWeight: FontWeight.bold),
                            ),
                          ),
                        ),

                        const SizedBox(height: 20),

                        // --- BOTÃO 2: SOLICITAÇÕES ---
                        SizedBox(
                          width: double.infinity,
                          height: 55,
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.grey[800], // Cinza escuro para diferenciar
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                            ),
                            onPressed: () => _abrirLink("https://drivetriunfante.com.br/solicitacoes.php"),
                            child: const Text(
                              "Solicitações",
                              style: TextStyle(fontSize: 18, color: Colors.white, fontWeight: FontWeight.bold),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
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