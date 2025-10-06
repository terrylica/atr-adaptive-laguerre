//+------------------------------------------------------------------+
//| IModule.mqh                                                      |
//| Base Module Interface                                            |
//| Defines the common interface for all modular components         |
//+------------------------------------------------------------------+
#property copyright "Modular Framework"
#property version   "1.00"

//+------------------------------------------------------------------+
//| Base Module Interface                                            |
//+------------------------------------------------------------------+
class IModule
{
protected:
    string            m_name;           // Module name
    bool              m_initialized;    // Initialization status
    string            m_error_message;  // Last error message

public:
    //--- Constructor/Destructor
                      IModule(string name = "BaseModule") : m_name(name), m_initialized(false) {}
    virtual          ~IModule() {}
    
    //--- Pure virtual methods (must be implemented by derived classes)
    virtual bool      Initialize() = 0;
    virtual void      Deinitialize() = 0;
    virtual bool      IsValid() = 0;
    
    //--- Common methods
    virtual string    GetName() const { return m_name; }
    virtual bool      IsInitialized() const { return m_initialized; }
    virtual string    GetLastError() const { return m_error_message; }
    
    //--- Protected helper methods
protected:
    virtual void      SetError(string error) { m_error_message = error; }
    virtual void      SetInitialized(bool status) { m_initialized = status; }
    virtual void      ResetError() { m_error_message = ""; }
};

//+------------------------------------------------------------------+
//| Module Manager Class                                             |
//| Manages a collection of modules                                  |
//+------------------------------------------------------------------+
class CModuleManager
{
private:
    IModule*          m_modules[];      // Array of module pointers
    int               m_count;          // Number of modules

public:
                      CModuleManager() : m_count(0) {}
                     ~CModuleManager() { CleanupModules(); }
    
    //--- Module management
    bool              AddModule(IModule* module);
    bool              RemoveModule(string name);
    IModule*          GetModule(string name);
    bool              InitializeAll();
    void              DeinitializeAll();
    void              CleanupModules();
    
    //--- Information
    int               GetModuleCount() const { return m_count; }
    string            GetModuleNames();
};

//+------------------------------------------------------------------+
//| Add module to manager                                            |
//+------------------------------------------------------------------+
bool CModuleManager::AddModule(IModule* module)
{
    if(module == NULL)
        return false;
        
    // Check if module with same name already exists
    if(GetModule(module.GetName()) != NULL)
        return false;
    
    // Resize array and add module
    ArrayResize(m_modules, m_count + 1);
    m_modules[m_count] = module;
    m_count++;
    
    return true;
}

//+------------------------------------------------------------------+
//| Remove module from manager                                       |
//+------------------------------------------------------------------+
bool CModuleManager::RemoveModule(string name)
{
    for(int i = 0; i < m_count; i++)
    {
        if(m_modules[i].GetName() == name)
        {
            // Deinitialize and delete module
            m_modules[i].Deinitialize();
            delete m_modules[i];
            
            // Shift remaining modules
            for(int j = i; j < m_count - 1; j++)
                m_modules[j] = m_modules[j + 1];
            
            m_count--;
            ArrayResize(m_modules, m_count);
            return true;
        }
    }
    return false;
}

//+------------------------------------------------------------------+
//| Get module by name                                               |
//+------------------------------------------------------------------+
IModule* CModuleManager::GetModule(string name)
{
    for(int i = 0; i < m_count; i++)
    {
        if(m_modules[i].GetName() == name)
            return m_modules[i];
    }
    return NULL;
}

//+------------------------------------------------------------------+
//| Initialize all modules                                           |
//+------------------------------------------------------------------+
bool CModuleManager::InitializeAll()
{
    bool success = true;
    for(int i = 0; i < m_count; i++)
    {
        if(!m_modules[i].Initialize())
        {
            Print("Failed to initialize module: ", m_modules[i].GetName(), 
                  " Error: ", m_modules[i].GetLastError());
            success = false;
        }
    }
    return success;
}

//+------------------------------------------------------------------+
//| Deinitialize all modules                                         |
//+------------------------------------------------------------------+
void CModuleManager::DeinitializeAll()
{
    for(int i = 0; i < m_count; i++)
    {
        m_modules[i].Deinitialize();
    }
}

//+------------------------------------------------------------------+
//| Cleanup all modules                                              |
//+------------------------------------------------------------------+
void CModuleManager::CleanupModules()
{
    for(int i = 0; i < m_count; i++)
    {
        if(m_modules[i] != NULL)
        {
            m_modules[i].Deinitialize();
            delete m_modules[i];
        }
    }
    ArrayFree(m_modules);
    m_count = 0;
}

//+------------------------------------------------------------------+
//| Get names of all modules                                         |
//+------------------------------------------------------------------+
string CModuleManager::GetModuleNames()
{
    string names = "";
    for(int i = 0; i < m_count; i++)
    {
        if(i > 0) names += ", ";
        names += m_modules[i].GetName();
    }
    return names;
} 