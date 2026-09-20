using System;
using System.Management.Automation;
using System.Management.Automation.Subsystem;

namespace CxxuPredictor
{
    public class Init : IModuleAssemblyInitializer, IModuleAssemblyCleanup
    {
        private const string Identifier = "cf099404-6c9b-4d2c-9118-a14c1368d97d";

        public void OnImport()
        {
            var predictor = new CxxuCommandPredictor(Identifier);
            SubsystemManager.RegisterSubsystem(SubsystemKind.CommandPredictor, predictor);
        }

        public void OnRemove(PSModuleInfo psModuleInfo)
        {
            SubsystemManager.UnregisterSubsystem(SubsystemKind.CommandPredictor, new Guid(Identifier));
        }
    }
}
