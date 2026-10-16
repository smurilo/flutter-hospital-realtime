import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../domain/board_logic.dart';
import '../domain/entities.dart';
import 'board_bloc.dart';

class BoardPage extends StatelessWidget {
  const BoardPage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<BoardBloc, BoardState>(
      listenWhen: (a, b) => b.message != null && a.message != b.message,
      listener: (context, state) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(state.message!))),
      builder: (context, state) => DefaultTabController(
        length: Ward.values.length,
        child: Scaffold(
          appBar: AppBar(
            title: const Text('Painel de Leitos'),
            actions: [_ConnectionChip(state.connection)],
            bottom: TabBar(
              isScrollable: true,
              onTap: (i) => context.read<BoardBloc>().add(WardSelected(Ward.values[i])),
              tabs: [for (final o in state.occupancy) Tab(text: '${o.ward.label} ${(o.rate * 100).round()}%')],
            ),
          ),
          body: state.board == null
              ? const Center(child: CircularProgressIndicator())
              : Column(
                  children: [
                    _OccupancyHeader(state.occupancy.firstWhere((o) => o.ward == state.ward)),
                    Expanded(
                      child: GridView.extent(
                        maxCrossAxisExtent: 140,
                        padding: const EdgeInsets.all(12),
                        mainAxisSpacing: 8,
                        crossAxisSpacing: 8,
                        children: [for (final bed in state.beds) _BedTile(bed)],
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}

class _ConnectionChip extends StatelessWidget {
  const _ConnectionChip(this.status);

  final ConnectionStatus status;

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (status) {
      ConnectionStatus.live => ('Ao vivo', Colors.green),
      ConnectionStatus.connecting => ('Conectando', Colors.blueGrey),
      ConnectionStatus.reconnecting => ('Reconectando', Colors.orange),
      ConnectionStatus.offline => ('Offline — dados podem estar desatualizados', Colors.red),
    };
    return Padding(
      padding: const EdgeInsets.only(right: 12),
      child: Chip(avatar: CircleAvatar(backgroundColor: color, radius: 5), label: Text(label)),
    );
  }
}

class _OccupancyHeader extends StatelessWidget {
  const _OccupancyHeader(this.o);

  final WardOccupancy o;

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        color: o.critical ? Colors.red.shade100 : Theme.of(context).colorScheme.surfaceContainerHighest,
        padding: const EdgeInsets.all(12),
        child: Text(
          '${o.critical ? '⚠️ OCUPAÇÃO CRÍTICA — ' : ''}${o.occupied}/${o.total} ocupados • ${o.free} livres • ${o.cleaning} em higienização',
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
      );
}

class _BedTile extends StatelessWidget {
  const _BedTile(this.bed);

  final Bed bed;

  @override
  Widget build(BuildContext context) {
    final (color, icon, label) = switch (bed.status) {
      BedStatus.free => (Colors.green, Icons.check_circle_outline, 'Livre'),
      BedStatus.occupied => (Colors.blue, Icons.person, 'Ocupado'),
      BedStatus.cleaning => (Colors.amber, Icons.cleaning_services, 'Higienização'),
      BedStatus.blocked => (Colors.grey, Icons.block, 'Bloqueado'),
    };
    return Semantics(
      label: 'Leito ${bed.code}, $label${bed.patientInitials != null ? ', paciente ${bed.patientInitials}' : ''}',
      button: bed.status == BedStatus.cleaning,
      excludeSemantics: true,
      child: Card(
        color: color.withValues(alpha: 0.15),
        shape:
            RoundedRectangleBorder(side: BorderSide(color: color, width: 2), borderRadius: BorderRadius.circular(12)),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: bed.status == BedStatus.cleaning ? () => _confirmCleaning(context) : null,
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(bed.code, style: Theme.of(context).textTheme.titleMedium),
                Icon(icon, color: color),
                Text(bed.patientInitials ?? label, style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _confirmCleaning(BuildContext context) async {
    final bloc = context.read<BoardBloc>();
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('Leito ${bed.code}'),
        content: const Text('Confirmar que a higienização foi concluída e liberar o leito?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Liberar leito')),
        ],
      ),
    );
    if (ok ?? false) bloc.add(CleaningConfirmed(bed.id));
  }
}
