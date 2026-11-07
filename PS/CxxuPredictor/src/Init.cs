using System;
using System.Management.Automation;
using System.Management.Automation.Subsystem;

namespace CxxuPredictor
{
    public class Init : IModuleAssemblyInitializer, IModuleAssemblyCleanup
    {
        private const string CommandIdentifier = "cf099404-6c9b-4d2c-9118-a14c1368d97d";
        private const string ArgcFlagsIdentifier = "3f6a2c1d-8b4e-4a7f-9c2d-5e1b0a9d7c34";

        public void OnImport()
        {
            var commandPredictor = new CxxuCommandPredictor(CommandIdentifier);
            SubsystemManager.RegisterSubsystem(SubsystemKind.CommandPredictor, commandPredictor);

            // 参数位静态 flag 提示:独立 GUID(可与命令名预测分开启停/排查);
            // 没有 argc-completions 仓库时表为空,自动不供稿。
            var flagsPredictor = new CxxuArgcFlagsPredictor(ArgcFlagsIdentifier);
            SubsystemManager.RegisterSubsystem(SubsystemKind.CommandPredictor, flagsPredictor);
        }

        public void OnRemove(PSModuleInfo psModuleInfo)
        {
            SubsystemManager.UnregisterSubsystem(SubsystemKind.CommandPredictor, new Guid(CommandIdentifier));
            SubsystemManager.UnregisterSubsystem(SubsystemKind.CommandPredictor, new Guid(ArgcFlagsIdentifier));
        }
    }
}
