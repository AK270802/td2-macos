mod capture_loop;
mod ipc;
mod sync_loop;

use anyhow::Result;
use tracing::info;

#[cfg(windows)]
mod service {
    use windows_service::{
        define_windows_service,
        service::{
            ServiceControl, ServiceControlAccept, ServiceExitCode,
            ServiceState, ServiceStatus, ServiceType,
        },
        service_control_handler::{self, ServiceControlHandlerResult},
        service_dispatcher,
    };
    use std::sync::atomic::{AtomicBool, Ordering};
    use std::sync::Arc;
    use std::time::Duration;

    const SERVICE_NAME: &str = "WorkPulseAgent";

    define_windows_service!(ffi_service_main, service_main);

    pub fn run_as_service() -> anyhow::Result<()> {
        service_dispatcher::start(SERVICE_NAME, ffi_service_main)?;
        Ok(())
    }

    fn service_main(_args: Vec<std::ffi::OsString>) {
        let _ = run_service_inner();
    }

    fn run_service_inner() -> anyhow::Result<()> {
        let shutdown = Arc::new(AtomicBool::new(false));
        let shutdown_clone = shutdown.clone();

        let handler = move |control: ServiceControl| -> ServiceControlHandlerResult {
            match control {
                ServiceControl::Stop | ServiceControl::Shutdown => {
                    shutdown_clone.store(true, Ordering::SeqCst);
                    ServiceControlHandlerResult::NoError
                }
                ServiceControl::Interrogate => ServiceControlHandlerResult::NoError,
                _ => ServiceControlHandlerResult::NotImplemented,
            }
        };

        let status_handle = service_control_handler::register(SERVICE_NAME, handler)?;
        status_handle.set_service_status(ServiceStatus {
            service_type: ServiceType::OWN_PROCESS,
            current_state: ServiceState::Running,
            controls_accepted: ServiceControlAccept::STOP | ServiceControlAccept::SHUTDOWN,
            exit_code: ServiceExitCode::Win32(0),
            checkpoint: 0,
            wait_hint: Duration::default(),
            process_id: None,
        })?;

        let rt = tokio::runtime::Runtime::new()?;
        rt.block_on(super::run_agent_loops(shutdown.clone()))?;

        status_handle.set_service_status(ServiceStatus {
            service_type: ServiceType::OWN_PROCESS,
            current_state: ServiceState::Stopped,
            controls_accepted: ServiceControlAccept::empty(),
            exit_code: ServiceExitCode::Win32(0),
            checkpoint: 0,
            wait_hint: Duration::default(),
            process_id: None,
        })?;
        Ok(())
    }

    pub fn install_service() -> anyhow::Result<()> {
        use windows_service::service::{ServiceAccess, ServiceErrorControl, ServiceInfo, ServiceStartType};
        use windows_service::service_manager::{ServiceManager, ServiceManagerAccess};
        let manager = ServiceManager::local_computer(None::<&str>, ServiceManagerAccess::CREATE_SERVICE)?;
        let exe = std::env::current_exe()?;
        manager.create_service(&ServiceInfo {
            name: SERVICE_NAME.into(),
            display_name: "WorkPulse Agent".into(),
            service_type: ServiceType::OWN_PROCESS,
            start_type: ServiceStartType::AutoStart,
            error_control: ServiceErrorControl::Normal,
            executable_path: exe,
            launch_arguments: vec!["run".into()],
            dependencies: vec![],
            account_name: None,
            account_password: None,
        }, ServiceAccess::CHANGE_CONFIG | ServiceAccess::START)?;
        configure_recovery()?;
        println!("Service installed: {SERVICE_NAME}");
        Ok(())
    }

    pub fn remove_service() -> anyhow::Result<()> {
        use windows_service::service::ServiceAccess;
        use windows_service::service_manager::{ServiceManager, ServiceManagerAccess};
        let manager = ServiceManager::local_computer(None::<&str>, ServiceManagerAccess::CONNECT)?;
        let service = manager.open_service(SERVICE_NAME, ServiceAccess::DELETE | ServiceAccess::STOP)?;
        let _ = service.stop();
        service.delete()?;
        println!("Service removed: {SERVICE_NAME}");
        Ok(())
    }

    fn configure_recovery() -> anyhow::Result<()> {
        // sc failure WorkPulseAgent reset= 86400 actions= restart/60000/restart/60000////
        std::process::Command::new("sc")
            .args(["failure", SERVICE_NAME, "reset=", "86400",
                   "actions=", "restart/60000/restart/60000////"])
            .output()?;
        Ok(())
    }
}

async fn run_agent_loops(shutdown: std::sync::Arc<std::sync::atomic::AtomicBool>) -> Result<()> {
    info!("WorkPulse agentd starting");
    let db = common::db::open()?;
    let client = common::api::build_client()?;

    // Startup: fetch config before UI is shown
    if let Ok((_config, tasks)) = common::api::agent::get_config(&client).await {
        common::db::queries::upsert_assigned_tasks(&db, &tasks)?;
        info!("Startup config fetched, {} tasks", tasks.len());
    }

    // Spawn IPC server (Send-safe, stays on tokio)
    let ipc_handle = tokio::spawn(ipc::run_ipc_server());

    // rusqlite::Connection is !Send; run each loop on its own OS thread
    // with a single-threaded runtime so the connection never crosses threads.
    std::thread::Builder::new().name("capture".into()).spawn(move || {
        let rt = tokio::runtime::Builder::new_current_thread()
            .enable_all().build().expect("capture rt");
        rt.block_on(capture_loop::run());
    })?;
    std::thread::Builder::new().name("sync".into()).spawn(move || {
        let rt = tokio::runtime::Builder::new_current_thread()
            .enable_all().build().expect("sync rt");
        rt.block_on(sync_loop::run());
    })?;

    // Heartbeat until shutdown
    while !shutdown.load(std::sync::atomic::Ordering::SeqCst) {
        tokio::time::sleep(std::time::Duration::from_secs(30)).await;
        info!("heartbeat");
    }

    ipc_handle.abort();
    info!("WorkPulse agentd stopped");
    Ok(())
}

fn main() -> Result<()> {
    tracing_subscriber::fmt()
        .with_env_filter(tracing_subscriber::EnvFilter::from_default_env())
        .init();

    let args: Vec<String> = std::env::args().collect();
    let cmd = args.get(1).map(|s| s.as_str()).unwrap_or("run");

    match cmd {
        #[cfg(windows)]
        "install" => service::install_service()?,
        #[cfg(windows)]
        "remove" => service::remove_service()?,
        #[cfg(windows)]
        "run" => service::run_as_service()?,
        "debug" => {
            let rt = tokio::runtime::Runtime::new()?;
            let shutdown = std::sync::Arc::new(std::sync::atomic::AtomicBool::new(false));
            let s2 = shutdown.clone();
            ctrlc::set_handler(move || { s2.store(true, std::sync::atomic::Ordering::SeqCst); })?;
            rt.block_on(run_agent_loops(shutdown))?;
        }
        _ => eprintln!("Usage: agentd [install|remove|run|debug]"),
    }
    Ok(())
}
