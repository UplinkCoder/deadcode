module gui.resources.shaderprogram;

static import graphics.shaderprogram;
import gui.locations;
import gui.resource;

import io.iomanager;

import jsonx;

import std.file;

class ShaderProgram : graphics.material.ShaderProgram, IResource!ShaderProgram
{
	private static @property ShaderProgram builtIn() { return null; } // hide

	@property 
	{
		string name()
		{
			return _name;
		}

		void name(string name)
		{
			_name = name;
		}

		Handle handle()
		{
			return _handle;
		}

		void handle(Handle h)
		{
			_handle = h;
		}
		
		URI uri()
		{
			return _manager.getURI(_handle);
		}

		Manager manager()
		{
			return _manager;
		}

		void manager(Manager m)
		{
			_manager = m;
		}

	}

	void load()
	{
		_manager.load(_handle);
	}

	void unload()
	{
		_manager.unload(_handle);
	}


	Manager _manager;
	Handle _handle;
	string _name;
}

class ShaderProgramManager : ResourceManager!ShaderProgram
{
	@property ShaderProgram builtinShaderProgram()
	{
		return get("builtin");
	}
	
	static ShaderProgramManager create(IOManager ioManager)
	{
		auto fm = new ShaderProgramManager;
		auto fp = new ShaderProgramSerializer;
		fm.ioManager = ioManager;
		fm.addSerializer(fp);

		fm.createBuiltinShaderProgram();

		return fm;
	}

	static class BuiltinLoader : Loader
	{
		bool load(ShaderProgram p, URI uri)
		{
			import graphics.shader;
			ShaderProgram.create(Shader.builtInVertexShaderSource, Shader.builtInFragmentShaderSource, p);
			p.link();
			p.setUniform("colMap", 0);
			p.manager.onResourceLoaded(p, null);
			return true;
		}
	}

	private void createBuiltinShaderProgram()
	{
		declare("builtin", null, new BuiltinLoader);
	}
}

class ShaderProgramSerializer : ResourceSerializer!ShaderProgram
{
	override bool canHandle(URI uri)
	{
		import std.path;
		return uri.extension == ".shaderprogram";
	}
	
	override void deserialize(ShaderProgram res, string str)
	{
		struct ShaderProgramSpec
		{
			string fragmentShader;
			string vertexShader;
		}
		import std.string;
		string[dchar] transTable;
		transTable['\n'] = "\\n";
		transTable['\t'] = "\\t";
		transTable['\r'] = "\\r";
		auto trStr = translate(str, transTable);
		auto spec = jsonDecode!ShaderProgramSpec(str);
		
		// TODO: Make explicit attach and link here!
		ShaderProgram.create(spec.vertexShader, spec.fragmentShader, res).link();
		res.manager.onResourceLoaded(res, this);
	}
}

