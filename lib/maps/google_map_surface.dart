        CameraUpdate.newLatLngZoom(LatLng(fix.latitude, fix.longitude), 16),
      );
    } catch (_) {
      if (mounted) {
        setState(
          () => _cameraError = 'Map camera unavailable. Try reopening the app.',
        );
      }
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final supported =
        !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
    const enabled = bool.fromEnvironment('MAPS_ENABLED');
    const key = String.fromEnvironment('GOOGLE_MAPS_API_KEY');
    if (!supported || !enabled || key.isEmpty) {
      return ColoredBox(
        color: const Color(0xffe8efeb),
        child: Center(
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.map_outlined, size: 56),
                  const SizedBox(height: 16),
                  Text(
                    !supported
                        ? 'Maps are not supported on this platform yet'
                        : 'Your map starts here',
                    style: Theme.of(context).textTheme.titleLarge,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    !supported
                        ? 'Use the Android application for this milestone.'
                        : 'Add a restricted Google Maps key using the setup guide. Live GPS and sensor diagnostics work independently.',
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }
    final fix = widget.fix;
    return Stack(
      children: [
        GoogleMap(
          initialCameraPosition: CameraPosition(
            target: fix == null
                ? const LatLng(0, 0)
                : LatLng(fix.latitude, fix.longitude),
            zoom: fix == null ? 2 : 16,
          ),
          onMapCreated: (controller) {
            _controller = controller;
            _center();
          },
          myLocationEnabled: false,