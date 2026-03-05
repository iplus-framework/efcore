## Error

```bash
026-02-18 11:49:39.366 [error] Microsoft.VisualStudio.TestPlatform.ObjectModel.TestPlatformException: Testhost process for source(s) 'C:\Devel\iplus-github\ef_main_iPlus\artifacts\bin\EFCore.Specification.Tests\Debug\net10.0\Microsoft.EntityFrameworkCore.Specification.Tests.dll' exited with error: Error:
  An assembly specified in the application dependencies manifest (Microsoft.EntityFrameworkCore.Specification.Tests.deps.json) was not found:
    package: 'Castle.Core', version: '5.2.1'
    path: 'lib/net6.0/Castle.Core.dll'
. Please check the diagnostic logs for more information.
   at Microsoft.VisualStudio.TestPlatform.CrossPlatEngine.Client.ProxyOperationManager.ThrowOnTestHostExited(IEnumerable`1 sources, Boolean testHostExited) in /_/src/vstest/src/Microsoft.TestPlatform.CrossPlatEngine/Client/ProxyOperationManager.cs:line 524
   at Microsoft.VisualStudio.TestPlatform.CrossPlatEngine.Client.ProxyOperationManager.SetupChannel(IEnumerable`1 sources, String runSettings) in /_/src/vstest/src/Microsoft.TestPlatform.CrossPlatEngine/Client/ProxyOperationManager.cs:line 293
   at Microsoft.VisualStudio.TestPlatform.CrossPlatEngine.Client.ProxyDiscoveryManager.InitializeDiscovery(DiscoveryCriteria discoveryCriteria, ITestDiscoveryEventsHandler2 eventHandler, Boolean skipDefaultAdapters) in /_/src/vstest/src/Microsoft.TestPlatform.CrossPlatEngine/Client/ProxyDiscoveryManager.cs:line 147

   ```